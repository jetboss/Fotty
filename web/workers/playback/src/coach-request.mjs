const MAX_BODY_BYTES = 48 * 1024;
const isRecord = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const isID = (value) => Number.isSafeInteger(value) && value > 0;
const optional = (value, valid) => value === undefined || valid(value);

function validContext(context) {
  if (!isRecord(context)) return false;
  for (const key of ["squad", "captains", "transferOptions"]) {
    const items = context[key];
    if (items === undefined) continue;
    if (!Array.isArray(items) || items.length > 30 || !items.every(isRecord)) return false;
    if (!items.every((item) => optional(item.id, isID))) return false;
    if (key === "transferOptions" && !items.every((item) =>
      isRecord(item.out) && isRecord(item.in)
      && isID(item.out.id) && isID(item.in.id))) return false;
  }
  return optional(context.profile, (profile) => isRecord(profile)
    && optional(profile.planningHorizon, (value) => Number.isInteger(value) && value >= 1 && value <= 8));
}

function validBody(body) {
  return isRecord(body)
    && typeof body.query === "string" && body.query.trim().length > 0 && body.query.trim().length <= 1200
    && optional(body.managerId, isID) && optional(body.rivalId, isID)
    && optional(body.context, validContext)
    && optional(body.history, (history) => Array.isArray(history) && history.length <= 8
      && history.every((item) => isRecord(item) && ["user", "assistant"].includes(item.role)
        && typeof item.content === "string" && item.content.length <= 8000));
}

export async function readCoachRequest(request) {
  const tooLarge = { error: "Coach request is too large.", status: 413 };
  if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) return tooLarge;
  const reader = request.body?.getReader();
  if (!reader) return { error: "Invalid Coach request body.", status: 400 };
  const chunks = [];
  let size = 0;
  try {
    // Enforce the limit while reading, including chunked requests with no length header.
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) {
        await reader.cancel().catch(() => {});
        return tooLarge;
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!validBody(body)) return { error: "Invalid Coach request shape, question, or history.", status: 400 };
    return { body: { ...body, query: body.query.trim() } };
  } catch {
    return { error: "Invalid JSON body.", status: 400 };
  } finally {
    reader.releaseLock();
  }
}

export async function checkCoachLimit(binding, key) {
  if (!binding) return null;
  try {
    const result = await binding.limit({ key });
    if (result?.success === true) return null;
    if (result?.success === false) return { error: "Coach rate limit reached. Try again in a minute.", status: 429 };
  } catch { /* A configured but failing limiter must not bypass the spending guard. */ }
  return { error: "The coach is temporarily unavailable. Try again shortly.", status: 503 };
}
