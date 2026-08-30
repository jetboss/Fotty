import assert from "node:assert/strict";
import test from "node:test";

/** Keep in sync with server/local-auth.ts */
function isLocalAuthEnabled(env) {
  if (env.NODE_ENV === "production") {
    return false;
  }
  return env.NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH === "true";
}

test("local auth is disabled in production even when flag is true", () => {
  assert.equal(
    isLocalAuthEnabled({
      NODE_ENV: "production",
      NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH: "true",
    }),
    false
  );
});

test("local auth follows flag in non-production", () => {
  assert.equal(
    isLocalAuthEnabled({
      NODE_ENV: "development",
      NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH: "true",
    }),
    true
  );
  assert.equal(
    isLocalAuthEnabled({
      NODE_ENV: "development",
      NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH: "false",
    }),
    false
  );
});
