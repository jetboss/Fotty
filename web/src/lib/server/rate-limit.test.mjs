import assert from "node:assert/strict";
import test from "node:test";

/** Keep in sync with rate-limit.ts */
const buckets = new Map();

function checkRateLimit(key, limit, windowMs) {
  const now = Date.now();
  const entry = buckets.get(key);

  if (!entry || now >= entry.resetAt) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }

  if (entry.count >= limit) return false;

  entry.count += 1;
  return true;
}

test("rate limit allows up to limit then blocks", () => {
  buckets.clear();
  const key = "admin-login:127.0.0.1";
  const limit = 8;
  const windowMs = 60_000;

  for (let i = 0; i < limit; i += 1) {
    assert.equal(checkRateLimit(key, limit, windowMs), true, `attempt ${i + 1}`);
  }
  assert.equal(checkRateLimit(key, limit, windowMs), false);
});

test("rate limit resets after window", () => {
  buckets.clear();
  const key = "admin-login:test";
  const limit = 2;
  const windowMs = 1_000;
  const now = Date.now();

  buckets.set(key, { count: 2, resetAt: now - 1 });

  assert.equal(checkRateLimit(key, limit, windowMs), true);
});
