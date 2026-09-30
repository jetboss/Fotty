// One request budget, revocable private access and one globally persisted
// paid-attempt allowance. Never log tokens, questions or manager identifiers.
export function coachDeadline(parentSignal, milliseconds = 50_000) {
  const controller = new AbortController();
  const abort = () => controller.abort(parentSignal?.reason || new DOMException("Cancelled", "AbortError"));
  if (parentSignal?.aborted) abort();
  else parentSignal?.addEventListener("abort", abort, { once: true });
  const timer = setTimeout(() => controller.abort(new DOMException("Deadline exceeded", "TimeoutError")), milliseconds);
  return {
    signal: controller.signal,
    dispose() {
      clearTimeout(timer);
      parentSignal?.removeEventListener("abort", abort);
      controller.abort(new DOMException("Request finished", "AbortError"));
    },
  };
}

export function abortable(operation, signal) {
  signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const abort = () => {
      signal?.removeEventListener("abort", abort);
      reject(signal.reason || new DOMException("Cancelled", "AbortError"));
    };
    signal?.addEventListener("abort", abort, { once: true });
    Promise.resolve().then(() => { signal?.throwIfAborted(); return operation(); })
      .then(resolve, reject).finally(() => signal?.removeEventListener("abort", abort));
  });
}

export async function boundedText(response, maxBytes, signal) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("Missing response body");
  const chunks = [];
  let size = 0;
  let complete = false;
  try {
    if (Number(response.headers.get("content-length")) > maxBytes) throw new Error("Response too large");
    while (true) {
      const { done, value } = await abortable(() => reader.read(), signal);
      if (done) { complete = true; break; }
      size += value.byteLength;
      if (size > maxBytes) throw new Error("Response too large");
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } finally {
    if (!complete) void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function boundedJSON(response, maxBytes, signal) {
  return JSON.parse(await boundedText(response, maxBytes, signal));
}

export function paidCoachLimit(env) {
  const value = String(env.FPL_COACH_DAILY_LIMIT ?? "");
  return /^[1-9][0-9]{0,3}$/.test(value) ? Number(value) : null;
}

export async function authorizePaidCoach(request, env) {
  if (env.FPL_COACH_PAID_ENABLED !== "1") {
    return { status: 503, error: "Cloud Coach is paused. Local FPL tools remain available." };
  }
  if (!paidCoachLimit(env) || !env.FPL_COACH_BUDGET) {
    return { status: 503, error: "Cloud Coach's daily allowance is not configured." };
  }
  let digests;
  try {
    if (typeof env.FPL_COACH_ACCESS_SHA256 !== "string" || env.FPL_COACH_ACCESS_SHA256.length > 20_000) throw new Error();
    digests = JSON.parse(env.FPL_COACH_ACCESS_SHA256);
    if (!Array.isArray(digests) || !digests.length || digests.length > 256
      || !digests.every((value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value))) throw new Error();
  } catch {
    return { status: 503, error: "Private Coach access is not configured." };
  }
  const token = request.headers.get("authorization")?.match(/^Bearer ([a-fA-F0-9]{64})$/)?.[1]?.toLowerCase();
  const denied = { status: 401, error: "Cloud Coach needs a private invitation code. Add it in Settings → Privacy & Security → Coach Access." };
  if (!token) return denied;
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  let accepted = false;
  for (const expected of digests) {
    let difference = 0;
    for (let index = 0; index < 64; index++) difference |= hash.charCodeAt(index) ^ expected.charCodeAt(index);
    accepted = accepted || difference === 0;
  }
  return accepted ? null : denied;
}

export async function reservePaidCoach(env, signal) {
  try {
    signal.throwIfAborted();
    const id = env.FPL_COACH_BUDGET.idFromName("private-coach-global-v1");
    const response = await abortable(() => env.FPL_COACH_BUDGET.get(id).fetch(
      new Request("https://coach-budget.invalid/reserve", { method: "POST", signal })
    ), signal);
    const result = await boundedJSON(response, 4096, signal);
    if (response.status === 200 && result.allowed === true && Number.isSafeInteger(result.remaining) && result.remaining >= 0) return null;
    if (response.status === 429) return { status: 429, error: "The group's daily Cloud Coach allowance is used. It resets at midnight UTC; local FPL tools remain available." };
  } catch { signal.throwIfAborted(); }
  return { status: 503, error: "The Coach allowance could not be checked. No model request was started." };
}

export class CoachQuotaBudget {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.queue = Promise.resolve();
  }

  async fetch(request) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/reserve") return Response.json({ error: "Not found" }, { status: 404 });
    // Serialization plus persistence-before-admission prevents concurrent edge
    // callers from sharing the last slot. This object has one global name.
    const result = this.queue.then(() => this.reserve());
    this.queue = result.then(() => undefined, () => undefined);
    try { return await result; }
    catch { return Response.json({ allowed: false }, { status: 503 }); }
  }

  async reserve() {
    const limit = paidCoachLimit(this.env);
    if (this.env.FPL_COACH_PAID_ENABLED !== "1" || !limit) return Response.json({ allowed: false }, { status: 503 });
    const day = new Date().toISOString().slice(0, 10);
    const old = await this.state.storage.get("daily-v1");
    if (old && (!/^\d{4}-\d{2}-\d{2}$/.test(old.day) || old.day > day || !Number.isSafeInteger(old.used) || old.used < 0)) {
      return Response.json({ allowed: false }, { status: 503 });
    }
    const used = old?.day === day ? old.used : 0;
    if (used >= limit) return Response.json({ allowed: false }, { status: 429 });
    await this.state.storage.put("daily-v1", { day, used: used + 1 });
    // Never refund ambiguous upstream failures: a provider may have charged.
    return Response.json({ allowed: true, remaining: limit - used - 1 });
  }
}
