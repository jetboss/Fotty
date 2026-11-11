// Optional operations-only delivery from the existing committed watchdog outbox.
// No addresses, provider bodies, media URLs or user viewing data enter storage/status.
export const OWNER_EMAIL_KEY = "watchdog-owner-email-v1";
export const OWNER_EMAIL_LIMITS = Object.freeze({ known: 513, pending: 64, batch: 16,
  attemptsPerDay: 12, minimumGapMs: 300_000, leaseMs: 120_000, timeoutMs: 10_000, cutoverWindowMs: 1_800_000, bytes: 128 * 1024 });
const SENDER = "watchdog@getfotty.com";
const OUTCOMES = new Set(["none", "submitted", "rejected", "ambiguous"]);
const ERRORS = new Set([null, "sender-not-verified", "recipient-not-allowed", "rate-limited", "service-rejected", "submission-ambiguous"]);
const scalar = (value, maximum = 96) => typeof value === "string" && value.length <= maximum && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value);
const integer = (value) => Number.isSafeInteger(value) && value >= 0;
const ownKeys = (value, fields) => value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).every((key) => fields.includes(key));
const noticeID = (value) => typeof value === "string" && /^production:notice:[1-9][0-9]{0,14}$/.test(value);
const emailAddress = (value) => typeof value === "string" && value.length <= 254
  && /^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/.test(value);
function utc(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)) return null;
  const time = Date.parse(value);
  return integer(time) && new Date(time).toISOString().slice(0, 19) === value.slice(0, 19) ? time : null;
}
async function hash(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function configuration(env, now) {
  // Only an explicit0 is an operator pause. A lost or invalid flag must not
  // quietly hide an established delivery queue after a deployment.
  if (env.FOTTY_OWNER_EMAIL_ENABLED === "0") return { enabled: false, state: "disabled" };
  if (env.FOTTY_OWNER_EMAIL_ENABLED !== "1") return { enabled: false, state: "flag-unset" };
  const activatedAt = utc(env.FOTTY_OWNER_EMAIL_ACTIVATED_AT);
  if (!integer(now) || activatedAt === null || activatedAt > now || !emailAddress(env.FOTTY_OWNER_EMAIL_RECIPIENT)
    || env.FOTTY_OWNER_EMAIL_SENDER !== SENDER || typeof env.FOTTY_OWNER_EMAIL?.send !== "function") {
    return { enabled: true, state: "configuration-pending" };
  }
  return { enabled: true, activatedAt, recipient: env.FOTTY_OWNER_EMAIL_RECIPIENT, sender: SENDER,
    binding: env.FOTTY_OWNER_EMAIL, test: env.FOTTY_OWNER_EMAIL_SEND_TEST === "1" };
}
function finiteNotice(value, now) {
  const time = utc(value?.time);
  if (!noticeID(value?.id) || !["confirmed", "resolved", "overflow"].includes(value.type)
    || !["source", "stage", "failureClass", "scope"].every((key) => scalar(value[key]))
    || !Number.isSafeInteger(value.generation) || value.generation < 1 || time === null || time > now + 30_000) {
    throw new Error("Invalid operations notice");
  }
  return Object.fromEntries(["id", "type", "source", "stage", "failureClass", "scope", "generation", "time"].map((key) => [key, value[key]]));
}
function validate(state) {
  if (!ownKeys(state, ["schema", "activation", "configuration", "known", "pending", "baselineCount", "testRequested", "testRequestedAt", "pendingTest",
    "fence", "lease", "retryBatch", "day", "attempts", "nextAt", "lastAttemptAt", "lastSubmittedAt", "submittedBatches", "ambiguousAttempts",
    "consecutiveFailures", "lastOutcome", "lastError", "capacity"])
    || state.schema !== 1 || !integer(state.activation) || !/^[a-f0-9]{64}$/.test(state.configuration)
    || !Array.isArray(state.known) || state.known.length > OWNER_EMAIL_LIMITS.known
    || !state.known.every(noticeID) || new Set(state.known).size !== state.known.length
    || !Array.isArray(state.pending) || state.pending.length > OWNER_EMAIL_LIMITS.pending
    || !integer(state.baselineCount) || state.baselineCount > state.known.length
    || !["testRequested", "pendingTest", "capacity"].every((key) => typeof state[key] === "boolean")
    || state.pendingTest && !state.testRequested || !integer(state.fence)
    || !/^\d{4}-\d{2}-\d{2}$/.test(state.day) || !integer(state.attempts) || state.attempts > OWNER_EMAIL_LIMITS.attemptsPerDay
    || !["nextAt", "submittedBatches", "ambiguousAttempts", "consecutiveFailures"].every((key) => integer(state[key]))
    || !["lastAttemptAt", "lastSubmittedAt", "testRequestedAt"].every((key) => state[key] === null || integer(state[key]))
    || state.testRequested !== (state.testRequestedAt !== null)
    || !OUTCOMES.has(state.lastOutcome) || !ERRORS.has(state.lastError)
    || new TextEncoder().encode(JSON.stringify(state)).length > OWNER_EMAIL_LIMITS.bytes) throw new Error("Invalid email state");
  const pending = state.pending.map((row) => finiteNotice(row, Number.MAX_SAFE_INTEGER));
  if (new Set(pending.map((row) => row.id)).size !== pending.length
    || pending.some((row) => !state.known.includes(row.id) || utc(row.time) <= state.activation
      || !ownKeys(row, ["id", "type", "source", "stage", "failureClass", "scope", "generation", "time"]))) throw new Error("Invalid email pending state");
  if (state.lease !== null) {
    const lease = state.lease;
    if (!ownKeys(lease, ["fence", "until", "ids", "test", "batchID"]) || !integer(lease.fence) || lease.fence < 1 || lease.fence > state.fence
      || !integer(lease.until) || typeof lease.test !== "boolean" || !/^FE-[a-f0-9]{24}$/.test(lease.batchID)
      || !Array.isArray(lease.ids) || lease.ids.length > OWNER_EMAIL_LIMITS.batch
      || new Set(lease.ids).size !== lease.ids.length || !lease.ids.every((id) => pending.some((row) => row.id === id))
      || lease.test && (!state.pendingTest || lease.ids.length !== 0) || !lease.test && lease.ids.length === 0) throw new Error("Invalid email lease");
  }
  if (state.retryBatch !== null) {
    const retry = state.retryBatch;
    if (!ownKeys(retry, ["test", "ids", "batchID"]) || typeof retry.test !== "boolean"
      || !/^FE-[a-f0-9]{24}$/.test(retry.batchID) || !Array.isArray(retry.ids)
      || retry.ids.length > OWNER_EMAIL_LIMITS.batch || new Set(retry.ids).size !== retry.ids.length
      || !retry.ids.every((id) => pending.some((row) => row.id === id))
      || retry.test && (!state.pendingTest || retry.ids.length !== 0) || !retry.test && retry.ids.length === 0) throw new Error("Invalid retry batch");
  }
  return state;
}
function blank(config, fingerprint, day) {
  return { schema: 1, activation: config.activatedAt, configuration: fingerprint, known: [], pending: [], baselineCount: 0,
    testRequested: false, testRequestedAt: null, pendingTest: false, fence: 0, lease: null, retryBatch: null, day, attempts: 0, nextAt: 0,
    lastAttemptAt: null, lastSubmittedAt: null, submittedBatches: 0, ambiguousAttempts: 0,
    consecutiveFailures: 0, lastOutcome: "none", lastError: null, capacity: false };
}
function summary(state, now) {
  const pendingCount = state.pending.length + Number(state.pendingTest);
  let status = state.capacity ? "capacity" : state.lease && state.lease.until > now ? "submitting"
    : pendingCount && state.attempts >= OWNER_EMAIL_LIMITS.attemptsPerDay && state.day === new Date(now).toISOString().slice(0, 10) ? "rate-limited"
      : pendingCount && state.lastOutcome === "ambiguous" ? "ambiguous"
        : pendingCount && state.lastOutcome === "rejected" ? "retry-pending" : pendingCount ? "pending" : "ready";
  return { enabled: true, state: status, pendingCount, baselineCount: state.baselineCount, submittedBatches: state.submittedBatches,
    attemptsToday: state.day === new Date(now).toISOString().slice(0, 10) ? state.attempts : 0,
    ambiguousAttempts: state.ambiguousAttempts, lastAttemptAt: state.lastAttemptAt, lastSubmittedAt: state.lastSubmittedAt,
    lastError: state.lastError, capacity: state.capacity,
    oldestPendingAt: pendingCount ? Math.min(...state.pending.map((row) => utc(row.time)), ...(state.pendingTest ? [state.testRequestedAt] : [])) : null };
}
function outcome(error) {
  const code = typeof error?.code === "string" ? error.code : null;
  const reasons = { E_SENDER_NOT_VERIFIED: "sender-not-verified", E_SENDER_DOMAIN_NOT_AVAILABLE: "sender-not-verified",
    E_RECIPIENT_NOT_ALLOWED: "recipient-not-allowed", E_RATE_LIMIT_EXCEEDED: "rate-limited", E_DAILY_LIMIT_EXCEEDED: "rate-limited",
    E_VALIDATION_ERROR: "service-rejected", E_FIELD_MISSING: "service-rejected", E_RECIPIENT_SUPPRESSED: "service-rejected",
    E_ACCOUNT_SUSPENDED: "service-rejected", E_DELIVERY_FAILED: "service-rejected" };
  return reasons[code] ? { kind: "rejected", reason: reasons[code] } : { kind: "ambiguous", reason: "submission-ambiguous" };
}
function content(batch) {
  const subject = batch.test ? `[Fotty watchdog] DELIVERY TEST ${batch.batchID}` : `[Fotty watchdog] ${batch.notices.length} operational updates ${batch.batchID}`;
  const lines = [batch.test ? "DELIVERY TEST ONLY — not a provider incident or recovery." : "Fotty operational metadata updates.",
    `Stable batch: ${batch.batchID}`, "A repeated batch ID can be a retry after an ambiguous submission.", ""];
  const groups = new Map();
  for (const event of batch.notices) {
    const key = `${event.source} / ${event.stage}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(event);
  }
  const localTime = new Intl.DateTimeFormat("en-TT", { timeZone: "America/Port_of_Spain", dateStyle: "medium", timeStyle: "short" });
  for (const [key, rows] of groups) {
    const consequence = rows.some((row) => row.type === "overflow") ? "Monitoring capacity needs attention; some new changes may not be observed."
      : rows.some((row) => row.type === "confirmed") ? "Source metadata could not be verified; some match options may be missing."
        : "Metadata checks recovered; this does not certify decoded playback.";
    lines.push(key, consequence, ...rows.map((row) => `- ${row.type}: ${row.failureClass} (${row.scope}), generation ${row.generation}; observed ${localTime.format(new Date(row.time))} Tobago (${row.time} UTC)`), "");
  }
  lines.push("Metadata/descriptor availability is not decoded playback proof.",
    "Email-service submission is not confirmation of inbox delivery or human reading.", "No automatic repair or deployment occurred.");
  return { subject, text: lines.join("\n") };
}

export class OwnerEmailDelivery {
  constructor(storage, env, { clock = Date.now, timeoutMs = OWNER_EMAIL_LIMITS.timeoutMs } = {}) {
    this.storage = storage; this.env = env; this.clock = clock;
    this.timeoutMs = Math.max(1, Math.min(timeoutMs, OWNER_EMAIL_LIMITS.timeoutMs));
  }
  async config(now) {
    const config = configuration(this.env, now);
    if (!config.state) config.fingerprint = await hash(JSON.stringify([config.activatedAt, config.sender, config.recipient]));
    return config;
  }
  async status(now = this.clock()) {
    const config = await this.config(now);
    if (config.state === "disabled") return { enabled: false, state: "disabled" };
    if (config.state) {
      try {
        const previous = await this.storage.get(OWNER_EMAIL_KEY);
        if (previous) { validate(previous); return { enabled: true, state: "configuration-mismatch" }; }
        return config.state === "flag-unset" ? { enabled: false, state: "disabled" }
          : { enabled: true, state: config.state };
      } catch { return { enabled: true, state: "state-unavailable" }; }
    }
    try {
      const stored = await this.storage.get(OWNER_EMAIL_KEY);
      if (!stored) return { enabled: true, state: now - config.activatedAt > OWNER_EMAIL_LIMITS.cutoverWindowMs ? "cutover-expired" : "awaiting-cutover", pendingCount: 0 };
      validate(stored);
      if (stored.configuration !== config.fingerprint || stored.activation !== config.activatedAt) return { enabled: true, state: "configuration-mismatch" };
      if (stored.lastAttemptAt !== null && stored.lastAttemptAt > now) return { enabled: true, state: "clock-skew" };
      return summary(stored, now);
    } catch { return { enabled: true, state: "state-unavailable" }; }
  }
  async drain(notices, now = this.clock()) {
    const config = await this.config(now);
    if (config.state) return this.status(now);
    try { return await this.perform(config, notices, now); }
    catch { return { enabled: true, state: "state-unavailable" }; }
  }
  async perform(config, notices, now) {
    if (!Array.isArray(notices) || notices.length > OWNER_EMAIL_LIMITS.known) throw new Error("Email source bound");
    const current = notices.map((row) => finiteNotice(row, now));
    if (new Set(current.map((row) => row.id)).size !== current.length) throw new Error("Duplicate email source notice");
    const ids = current.filter((row) => utc(row.time) > config.activatedAt).map((row) => row.id);
    // Hash each possible bounded prefix outside the transaction; no async
    // external action can occur until its exact batch lease has been stored.
    const makeBatchID = (test, selected) => hash(JSON.stringify([config.activatedAt, test, selected])).then((value) => `FE-${value.slice(0, 24)}`);
    const possible = new Map();
    possible.set("test", await makeBatchID(true, []));
    // Existing pending notices may not be in a newer source list after an
    // operator failure; preserve them and derive the batch inside the snapshot.
    const previous = await this.storage.get(OWNER_EMAIL_KEY);
    if (previous) validate(previous);
    const pendingIDs = previous?.pending.map((row) => row.id) || [];
    const ordered = [...pendingIDs, ...ids.filter((id) => !previous?.known.includes(id))];
    for (let length = 1; length <= Math.min(OWNER_EMAIL_LIMITS.batch, ordered.length); length++) {
      const selected = ordered.slice(0, length); possible.set(selected.join("|"), await makeBatchID(false, selected));
    }
    const batch = await this.storage.transaction(async (transaction) => {
      const old = await transaction.get(OWNER_EMAIL_KEY);
      if (!old && now - config.activatedAt > OWNER_EMAIL_LIMITS.cutoverWindowMs) return null;
      const state = old ? validate(old) : blank(config, config.fingerprint, new Date(now).toISOString().slice(0, 10));
      if (state.configuration !== config.fingerprint || state.activation !== config.activatedAt) return null;
      if (state.lastAttemptAt !== null && state.lastAttemptAt > now) return null;
      const before = JSON.stringify(state), known = new Set(state.known);
      state.capacity = false;
      for (const row of current) {
        if (known.has(row.id)) continue;
        if (state.known.length >= OWNER_EMAIL_LIMITS.known || utc(row.time) > config.activatedAt && state.pending.length >= OWNER_EMAIL_LIMITS.pending) {
          state.capacity = true; continue;
        }
        known.add(row.id); state.known.push(row.id);
        if (utc(row.time) <= config.activatedAt) state.baselineCount++;
        else state.pending.push(row);
      }
      if (config.test && !state.testRequested) { state.testRequested = true; state.testRequestedAt = now; state.pendingTest = true; }
      if (state.lease && state.lease.until <= now) {
        const { test, ids, batchID } = state.lease;
        state.retryBatch = { test, ids, batchID };
        state.lease = null; state.lastOutcome = "ambiguous"; state.lastError = "submission-ambiguous"; state.ambiguousAttempts++;
      }
      const day = new Date(now).toISOString().slice(0, 10);
      if (state.day !== day) { state.day = day; state.attempts = 0; }
      let selected = null;
      if (!state.lease && state.nextAt <= now && state.attempts < OWNER_EMAIL_LIMITS.attemptsPerDay
        && (state.pendingTest || state.pending.length)) {
        const retry = state.retryBatch, test = retry?.test ?? state.pendingTest;
        const entries = test ? [] : retry ? state.pending.filter((row) => retry.ids.includes(row.id)) : state.pending.slice(0, OWNER_EMAIL_LIMITS.batch);
        const batchID = retry?.batchID || possible.get(test ? "test" : entries.map((row) => row.id).join("|"));
        // A competing transaction changed the queue. Leave it pending and
        // derive a new exact prefix on the next cron, never send a guessed batch.
        if (batchID && state.fence < Number.MAX_SAFE_INTEGER) {
          state.fence++; state.attempts++; state.lastAttemptAt = now; state.nextAt = now + OWNER_EMAIL_LIMITS.minimumGapMs;
          state.lease = { fence: state.fence, until: now + OWNER_EMAIL_LIMITS.leaseMs, test, batchID, ids: entries.map((row) => row.id) };
          selected = { ...state.lease, notices: entries };
        }
      }
      validate(state);
      if (before !== JSON.stringify(state) || !old) await transaction.put(OWNER_EMAIL_KEY, state);
      return selected;
    });
    if (!batch) return this.status(now);
    let result, timer;
    try {
      const message = content(batch);
      result = await Promise.race([Promise.resolve().then(() => config.binding.send({ to: config.recipient, from: config.sender,
        ...message, headers: { "X-Fotty-Alert-ID": batch.batchID } })),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("Ambiguous email deadline")), this.timeoutMs); })]);
      if (!result || typeof result.messageId !== "string" || result.messageId.length < 1 || result.messageId.length > 512
        || result.messageId.trim() !== result.messageId || result.messageId.includes("\0")
        || /[\r\n]/.test(result.messageId)) throw new Error("Email submission response unavailable");
      result = { kind: "submitted", reason: null };
    } catch (error) { result = outcome(error); }
    finally { clearTimeout(timer); }
    const completedAt = this.clock();
    await this.storage.transaction(async (transaction) => {
      const state = validate(await transaction.get(OWNER_EMAIL_KEY));
      if (state.configuration !== config.fingerprint || state.lease?.fence !== batch.fence || state.lease.batchID !== batch.batchID) return;
      state.lease = null; state.lastOutcome = result.kind; state.lastError = result.reason;
      if (result.kind === "submitted") {
        if (batch.test) state.pendingTest = false;
        else state.pending = state.pending.filter((row) => !batch.ids.includes(row.id));
        state.submittedBatches++; state.lastSubmittedAt = Math.max(now, completedAt); state.consecutiveFailures = 0;
        state.retryBatch = null;
      } else {
        state.retryBatch = { test: batch.test, ids: batch.ids, batchID: batch.batchID };
        state.consecutiveFailures++;
        if (result.kind === "ambiguous") state.ambiguousAttempts++;
        state.nextAt = Math.max(state.nextAt, now + Math.min(3_600_000, OWNER_EMAIL_LIMITS.minimumGapMs * 2 ** Math.min(4, state.consecutiveFailures - 1)));
      }
      validate(state); await transaction.put(OWNER_EMAIL_KEY, state);
    });
    return this.status(Math.max(now, completedAt));
  }
}
