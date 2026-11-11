import test from "node:test";
import assert from "node:assert/strict";
import { OwnerEmailDelivery, OWNER_EMAIL_KEY, OWNER_EMAIL_LIMITS } from "../../web/workers/watchdog/src/owner-email.mjs";

const START = Date.parse("2026-10-30T00:00:00.000Z");
function storage() {
  const values = new Map(); let queue = Promise.resolve(), writes = 0, failedWrite = Infinity;
  return { values, get writes() { return writes; }, failAt(value) { failedWrite = value; },
    async get(key) { return structuredClone(values.get(key)); },
    async transaction(change) {
      const task = queue.then(async () => {
        const staged = new Map(structuredClone([...values]));
        const result = await change({ get: async (key) => structuredClone(staged.get(key)), put: async (key, value) => {
          if (++writes === failedWrite) throw new Error("synthetic storage failure"); staged.set(key, structuredClone(value));
        } });
        values.clear(); for (const [key, value] of staged) values.set(key, value);
        return result;
      });
      queue = task.catch(() => {}); return task;
    } };
}
function fixture(overrides = {}) {
  const state = storage(), calls = []; let now = START;
  const env = { FOTTY_OWNER_EMAIL_ENABLED: "1", FOTTY_OWNER_EMAIL_ACTIVATED_AT: new Date(START).toISOString(),
    FOTTY_OWNER_EMAIL_RECIPIENT: "owner@receiver.example", FOTTY_OWNER_EMAIL_SENDER: "watchdog@getfotty.com",
    FOTTY_OWNER_EMAIL: { send: async (message) => { calls.push(message); return { messageId: `accepted-${calls.length}` }; } }, ...overrides };
  return { state, calls, env, at(value) { now = value; }, client(options = {}) {
    return new OwnerEmailDelivery(state, env, { clock: () => now, timeoutMs: 20, ...options });
  } };
}
const notice = (number = 1, at = START + 1, changes = {}) => ({ id: `production:notice:${number}`, type: "confirmed",
  source: "cs", stage: "catalog", failureClass: "schema", scope: "global", generation: 1,
  time: new Date(at).toISOString(), key: "unused private source facts", ...changes });

test("email source default is OFF and missing binding/address/cutover never writes or sends", async () => {
  for (const change of [{ FOTTY_OWNER_EMAIL_ENABLED: "0" }, { FOTTY_OWNER_EMAIL: undefined },
    { FOTTY_OWNER_EMAIL_RECIPIENT: "<PENDING>" }, { FOTTY_OWNER_EMAIL_RECIPIENT: "owner@example.com\r\nBcc:other@example.com" },
    { FOTTY_OWNER_EMAIL_SENDER: "other@getfotty.com" }, { FOTTY_OWNER_EMAIL_SENDER: "watchdog@other.example" },
    { FOTTY_OWNER_EMAIL_ACTIVATED_AT: "2026-02-30T00:00:00Z" }, { FOTTY_OWNER_EMAIL_ACTIVATED_AT: "2099-01-01T00:00:00Z" }]) {
    const f = fixture(change); f.at(START + 1);
    const result = await f.client().drain([notice()]);
    assert.ok(["disabled", "configuration-pending"].includes(result.state));
    assert.equal(f.calls.length, 0); assert.equal(f.state.writes, 0);
  }
});
test("explicit fresh cutover baselines all121 historical notices and never replays them after restart", async () => {
  const f = fixture(), historical = Array.from({ length: 121 }, (_, index) => notice(index + 1, START - 1));
  let result = await f.client().drain(historical);
  assert.equal(result.baselineCount, 121); assert.equal(result.pendingCount, 0); assert.equal(f.calls.length, 0);
  f.at(START + 1);
  result = await f.client().drain([...historical, notice(122)]);
  assert.equal(result.submittedBatches, 1); assert.equal(result.pendingCount, 0); assert.equal(f.calls.length, 1);
  assert.match(f.calls[0].subject, /1 operational updates/);
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs);
  result = await f.client().drain([...historical, notice(122)]);
  assert.equal(f.calls.length, 1); assert.equal(result.baselineCount, 121);
  assert.equal(f.state.values.get(OWNER_EMAIL_KEY).known.length, 122);
});
test("an old initial cutover fails closed instead of replaying retained history", async () => {
  const f = fixture(); f.at(START + OWNER_EMAIL_LIMITS.cutoverWindowMs + 1);
  assert.equal((await f.client().drain([notice()])).state, "cutover-expired");
  assert.equal(f.calls.length, 0); assert.equal(f.state.writes, 0);
});
test("only sanitized operations fields enter grouped text/state/status; target and raw facts stay private", async () => {
  const f = fixture(); f.at(START + 1);
  const rows = [notice(1), notice(2, START + 1, { failureClass: "metadata-unavailable" }),
    notice(3, START + 1, { source: "as", scope: "football", key: "https://media.invalid/private?token=secret-team-device" })];
  const result = await f.client().drain(rows), email = f.calls[0];
  assert.equal(email.to, f.env.FOTTY_OWNER_EMAIL_RECIPIENT); assert.equal(email.from, "watchdog@getfotty.com");
  assert.deepEqual(Object.keys(email).sort(), ["from", "headers", "subject", "text", "to"]);
  assert.match(email.text, /cs \/ catalog/); assert.match(email.text, /as \/ catalog/);
  assert.match(email.text, /some match options may be missing/); assert.match(email.text, /Tobago/);
  assert.match(email.text, /not confirmation of inbox delivery or human reading/);
  for (const value of [email.text, JSON.stringify([...f.state.values]), JSON.stringify(result)]) {
    assert.ok(!value.includes("private?token")); assert.ok(!value.includes("secret-team-device"));
    assert.ok(!value.includes(f.env.FOTTY_OWNER_EMAIL_RECIPIENT)); assert.ok(!value.includes("watchdog@getfotty.com"));
  }
});
test("malformed or duplicate notices fail closed without sending or accepting state", async () => {
  for (const rows of [[notice(), notice()], [notice(1, START + 1, { source: "url/secret" })],
    [notice(1, START + 1, { scope: "owner@private.example" })], [notice(1, START + 1, { type: "playback" })],
    [notice(1, START + 60_000)]]) {
    const f = fixture(); f.at(START + 1);
    assert.equal((await f.client().drain(rows)).state, "state-unavailable");
    assert.equal(f.calls.length, 0); assert.equal(f.state.writes, 0);
  }
});
test("overlapping delivery objects and restart share one stored send lease", async () => {
  let release, started; const ready = new Promise((resolve) => { started = resolve; });
  const f = fixture(); f.at(START + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); started(); return new Promise((resolve) => { release = resolve; }); };
  const first = f.client({ timeoutMs: 1000 }).drain([notice()]); await ready;
  const other = await f.client().drain([notice()]);
  assert.equal(other.state, "submitting"); assert.equal(f.calls.length, 1);
  release({ messageId: "accepted-once" });
  assert.equal((await first).pendingCount, 0); assert.equal(f.calls.length, 1);
});
test("an expired attempt cannot acknowledge or overwrite a newer lease's completed batch", async () => {
  let release, started; const ready = new Promise((resolve) => { started = resolve; });
  const f = fixture(); f.at(START + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => {
    f.calls.push(message);
    if (f.calls.length === 1) { started(); return new Promise((resolve) => { release = resolve; }); }
    return { messageId: "newer-accepted" };
  };
  const old = f.client({ timeoutMs: 1000 }).drain([notice()]); await ready;
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  const current = await f.client().drain([notice()]);
  assert.equal(current.pendingCount, 0); assert.equal(current.submittedBatches, 1); assert.equal(current.ambiguousAttempts, 1);
  const saved = structuredClone(f.state.values.get(OWNER_EMAIL_KEY));
  release({ messageId: "late-old-accepted" }); await old;
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), saved); assert.equal(f.calls.length, 2);
});
test("opaque provider acknowledgement is validated but never stored; a regressed clock cannot retry", async () => {
  const f = fixture(); f.at(START + 100);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); return { messageId: "<opaque@service.example>" }; };
  assert.equal((await f.client().drain([notice()])).submittedBatches, 1);
  assert.ok(!JSON.stringify([...f.state.values]).includes("opaque@service.example"));
  const saved = structuredClone(f.state.values.get(OWNER_EMAIL_KEY)); f.at(START + 2);
  assert.equal((await f.client().drain([notice()])).state, "clock-skew");
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), saved); assert.equal(f.calls.length, 1);
});
test("known platform rejection remains pending with bounded retry and no immediate duplicate", async () => {
  const f = fixture(); f.at(START + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); throw Object.assign(new Error("private address must not leak"), { code: "E_SENDER_NOT_VERIFIED" }); };
  let result = await f.client().drain([notice()]);
  assert.equal(result.state, "retry-pending"); assert.equal(result.lastError, "sender-not-verified");
  assert.equal(result.pendingCount, 1); assert.equal(result.submittedBatches, 0);
  f.at(START + 2); await f.client().drain([notice()]); assert.equal(f.calls.length, 1);
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); return { messageId: "accepted-retry" }; };
  result = await f.client().drain([notice()]); assert.equal(result.pendingCount, 0); assert.equal(f.calls.length, 2);
  assert.equal(f.calls[0].headers["X-Fotty-Alert-ID"], f.calls[1].headers["X-Fotty-Alert-ID"]);
});
test("new arrivals or a recovery cannot change an outstanding retry batch ID or overtake it", async () => {
  const f = fixture(); f.at(START + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); throw new Error("ambiguous transport"); };
  await f.client().drain([notice()]);
  const recovered = notice(2, START + 2, { type: "resolved" });
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); return { messageId: "accepted" }; };
  const firstRetry = await f.client().drain([notice(), recovered]);
  assert.equal(firstRetry.pendingCount, 1);
  assert.equal(f.calls[0].headers["X-Fotty-Alert-ID"], f.calls[1].headers["X-Fotty-Alert-ID"]);
  assert.ok(!f.calls[1].text.includes("resolved:"));
  f.at(START + 2 * OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  assert.equal((await f.client().drain([notice(), recovered])).pendingCount, 0);
  assert.match(f.calls[2].text, /resolved:/);
  assert.notEqual(f.calls[2].headers["X-Fotty-Alert-ID"], f.calls[1].headers["X-Fotty-Alert-ID"]);
});
test("timeout or missing service acknowledgement is ambiguous, never counted submitted", async () => {
  for (const kind of ["timeout", "missing-result", "blank-id", "transport"]) {
    const f = fixture(); f.at(START + 1);
    f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message);
      if (kind === "timeout") return new Promise(() => {});
      if (kind === "transport") throw new Error("private transport text");
      if (kind === "blank-id") return { messageId: " " };
      return undefined;
    };
    const result = await f.client({ timeoutMs: 1 }).drain([notice()]);
    assert.equal(result.state, "ambiguous"); assert.equal(result.pendingCount, 1);
    assert.equal(result.submittedBatches, 0); assert.equal(result.ambiguousAttempts, 1);
    assert.equal(result.lastError, "submission-ambiguous");
  }
});
test("a send before failed acknowledgement storage retries the same batch after lease expiry, honestly permitting duplicates", async () => {
  const f = fixture(); f.at(START + 1); f.state.failAt(2);
  assert.equal((await f.client().drain([notice()])).state, "state-unavailable");
  assert.equal(f.calls.length, 1); assert.equal(f.state.values.get(OWNER_EMAIL_KEY).pending.length, 1);
  assert.equal(f.state.values.get(OWNER_EMAIL_KEY).submittedBatches, 0);
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  const result = await f.client().drain([notice()]);
  assert.equal(f.calls.length, 2); assert.equal(result.ambiguousAttempts, 1);
  assert.equal(result.pendingCount, 0); assert.equal(result.submittedBatches, 1);
  assert.equal(f.calls[0].headers["X-Fotty-Alert-ID"], f.calls[1].headers["X-Fotty-Alert-ID"]);
});
test("failure to store the lease cannot send; corrupt state cannot reset the baseline", async () => {
  const f = fixture(); f.at(START + 1); f.state.failAt(1);
  assert.equal((await f.client().drain([notice()])).state, "state-unavailable"); assert.equal(f.calls.length, 0);
  f.state.values.set(OWNER_EMAIL_KEY, { schema: 99 });
  assert.equal((await f.client().drain([notice()])).state, "state-unavailable"); assert.equal(f.calls.length, 0);
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), { schema: 99 });
});
test("pending data survives disable/re-enable; changed destination or cutover cannot silently reset state", async () => {
  const f = fixture(); f.at(START + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async () => { throw new Error("unknown send outcome"); };
  await f.client().drain([notice()]); const saved = structuredClone(f.state.values.get(OWNER_EMAIL_KEY));
  f.env.FOTTY_OWNER_EMAIL_ENABLED = "0"; assert.equal((await f.client().drain([notice()])).state, "disabled");
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), saved);
  f.env.FOTTY_OWNER_EMAIL_ENABLED = "1"; f.env.FOTTY_OWNER_EMAIL_RECIPIENT = "different@receiver.example";
  assert.equal((await f.client().drain([notice()])).state, "configuration-mismatch");
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), saved);
  f.env.FOTTY_OWNER_EMAIL_RECIPIENT = "owner@receiver.example";
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); return { messageId: "resumed" }; };
  assert.equal((await f.client().drain([notice()])).pendingCount, 0);
});
test("a removed binding after established cutover is an actionable mismatch rather than quiet unconfigured staging", async () => {
  const f = fixture(); await f.client().drain([]);
  const original = structuredClone(f.state.values.get(OWNER_EMAIL_KEY));
  f.env.FOTTY_OWNER_EMAIL = undefined;
  assert.equal((await f.client().status()).state, "configuration-mismatch");
  assert.equal((await f.client().drain([])).state, "configuration-mismatch");
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), original); assert.equal(f.calls.length, 0);
});
test("missing or invalid enablement after an established pending cutover is actionable without sends or state changes", async () => {
  const f = fixture(); f.at(START + 1);
  f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); throw new Error("unknown submission outcome"); };
  assert.equal((await f.client().drain([notice()])).state, "ambiguous");
  const saved = structuredClone(f.state.values.get(OWNER_EMAIL_KEY)), writes = f.state.writes;
  assert.equal(saved.pending.length, 1);
  for (const flag of [undefined, "", "true", "garbled", 0]) {
    if (flag === undefined) delete f.env.FOTTY_OWNER_EMAIL_ENABLED;
    else f.env.FOTTY_OWNER_EMAIL_ENABLED = flag;
    assert.deepEqual(await f.client().status(), { enabled: true, state: "configuration-mismatch" });
    assert.deepEqual(await f.client().drain([notice()]), { enabled: true, state: "configuration-mismatch" });
    assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), saved);
    assert.equal(f.state.writes, writes); assert.equal(f.calls.length, 1);
  }
  f.env.FOTTY_OWNER_EMAIL_ENABLED = "0";
  assert.deepEqual(await f.client().status(), { enabled: false, state: "disabled" });
  assert.deepEqual(await f.client().drain([notice()]), { enabled: false, state: "disabled" });
  assert.deepEqual(f.state.values.get(OWNER_EMAIL_KEY), saved); assert.equal(f.state.writes, writes); assert.equal(f.calls.length, 1);
});
test("pristine missing enablement stays quiet without creating email state or sending", async () => {
  const f = fixture(); delete f.env.FOTTY_OWNER_EMAIL_ENABLED;
  assert.deepEqual(await f.client().status(), { enabled: false, state: "disabled" });
  assert.deepEqual(await f.client().drain([notice()]), { enabled: false, state: "disabled" });
  assert.equal(f.state.values.has(OWNER_EMAIL_KEY), false); assert.equal(f.state.writes, 0); assert.equal(f.calls.length, 0);
});
test("the optional labelled test is separate and submitted at most once per cutover", async () => {
  const f = fixture({ FOTTY_OWNER_EMAIL_SEND_TEST: "1" }); f.at(START + 1);
  let result = await f.client().drain([notice()]); assert.equal(result.pendingCount, 1);
  assert.match(f.calls[0].subject, /DELIVERY TEST/); assert.ok(!f.calls[0].text.includes("confirmed: schema"));
  f.at(START + OWNER_EMAIL_LIMITS.minimumGapMs + 1);
  result = await f.client().drain([notice()]); assert.equal(result.pendingCount, 0);
  assert.equal(f.calls.length, 2); assert.match(f.calls[1].subject, /operational updates/);
  f.at(START + 2 * OWNER_EMAIL_LIMITS.minimumGapMs + 1); await f.client().drain([notice()]); assert.equal(f.calls.length, 2);
});
test("daily attempts and backoff remain bounded across restart and UTC rollover", async () => {
  const f = fixture(); f.env.FOTTY_OWNER_EMAIL.send = async (message) => { f.calls.push(message); throw new Error("unknown"); };
  let now = START + 1, result;
  for (let index = 0; index < OWNER_EMAIL_LIMITS.attemptsPerDay; index++) {
    f.at(now); result = await f.client().drain([notice()]);
    now = f.state.values.get(OWNER_EMAIL_KEY).nextAt;
  }
  f.at(now); result = await f.client().drain([notice()]);
  assert.equal(result.state, "rate-limited"); assert.equal(f.calls.length, 12);
  f.at(START + 86_400_001); await f.client().drain([notice()]); assert.equal(f.calls.length, 13);
});
test("pending capacity never marks unsaved notices known or removes original source notices", async () => {
  const f = fixture(); f.at(START + 1);
  const rows = Array.from({ length: 80 }, (_, index) => notice(index + 1)); const original = structuredClone(rows);
  let result = await f.client().drain(rows);
  assert.equal(result.capacity, true); assert.equal(f.state.values.get(OWNER_EMAIL_KEY).known.length, 64);
  assert.equal(result.pendingCount, 48);
  for (let turn = 1; turn < 5; turn++) { f.at(START + turn * OWNER_EMAIL_LIMITS.minimumGapMs + 1); result = await f.client().drain(rows); }
  assert.equal(result.pendingCount, 0); assert.equal(f.state.values.get(OWNER_EMAIL_KEY).known.length, 80);
  assert.deepEqual(rows, original); assert.equal(f.calls.length, 5);
});
