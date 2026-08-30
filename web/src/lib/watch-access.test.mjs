import assert from "node:assert/strict";
import test from "node:test";

/** Keep in sync with watch-access.ts. */
function getWatchAccess(session, entitlement, { accountsEnabled = false, allowLocalAuth = false } = {}) {
  if (!accountsEnabled) {
    return { allowed: true, reason: null };
  }
  if (!session?.email) {
    return { allowed: false, reason: "sign_in" };
  }
  if (!entitlement.isPaid) {
    return { allowed: false, reason: "upgrade" };
  }
  if (!session.token && !(allowLocalAuth && session.provider === "local")) {
    return { allowed: false, reason: "refresh" };
  }
  return { allowed: true, reason: null };
}

const paid = { isPaid: true, plan: "plus" };

test("getWatchAccess opens Watch when accounts are disabled", () => {
  const result = getWatchAccess(null, { isPaid: false }, { accountsEnabled: false });
  assert.equal(result.allowed, true);
  assert.equal(result.reason, null);
});

test("getWatchAccess requires sign-in when accounts enabled", () => {
  const result = getWatchAccess(null, paid, { accountsEnabled: true });
  assert.equal(result.allowed, false);
  assert.equal(result.reason, "sign_in");
});

test("getWatchAccess requires paid entitlement when accounts enabled", () => {
  const result = getWatchAccess(
    { email: "fan@fotty.app", token: "tok" },
    { isPaid: false },
    { accountsEnabled: true }
  );
  assert.equal(result.allowed, false);
  assert.equal(result.reason, "upgrade");
});

test("getWatchAccess requires bearer token for paid users when accounts enabled", () => {
  const result = getWatchAccess({ email: "fan@fotty.app", entitlement: "plus" }, paid, {
    accountsEnabled: true,
  });
  assert.equal(result.allowed, false);
  assert.equal(result.reason, "refresh");
});

test("getWatchAccess allows paid session with token when accounts enabled", () => {
  const result = getWatchAccess({ email: "fan@fotty.app", token: "pb-token" }, paid, {
    accountsEnabled: true,
  });
  assert.equal(result.allowed, true);
  assert.equal(result.reason, null);
});
