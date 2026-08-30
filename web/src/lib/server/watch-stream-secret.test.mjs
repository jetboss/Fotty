import assert from "node:assert/strict";
import test from "node:test";

/** Keep in sync with server/watch-stream-secret.ts */
function getWatchStreamSecret(env) {
  return env.FOTTY_WATCH_STREAM_SECRET?.trim() || "";
}

test("watch stream secret does not fall back to billing webhook secret", () => {
  assert.equal(
    getWatchStreamSecret({
      FOTTY_BILLING_WEBHOOK_SECRET: "billing-only",
      FOTTY_WATCH_STREAM_SECRET: "",
    }),
    ""
  );
});

test("watch stream secret uses dedicated env var", () => {
  assert.equal(
    getWatchStreamSecret({
      FOTTY_WATCH_STREAM_SECRET: "watch-only",
      FOTTY_BILLING_WEBHOOK_SECRET: "billing-only",
    }),
    "watch-only"
  );
});
