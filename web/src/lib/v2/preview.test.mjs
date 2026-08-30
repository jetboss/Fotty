import test from "node:test";
import assert from "node:assert/strict";

function isV2Enabled(env) {
  if (env.NEXT_PUBLIC_FOTTY_V2_ENABLED === "true") return true;
  if (env.NODE_ENV === "production") return false;
  return (
    env.NEXT_PUBLIC_FOTTY_PREVIEW_ROUTES_ENABLED === "true" ||
    env.FOTTY_PREVIEW_ROUTES_ENABLED === "true"
  );
}

function v2SearchPath(env) {
  return isV2Enabled(env) ? "/search" : "/next/search";
}

function v2CanonicalFromNextPath(pathname) {
  if (!pathname.startsWith("/next")) return null;
  const suffix = pathname.slice("/next".length) || "/";
  return suffix === "/" ? "/" : suffix;
}

test("production v2 flag enables canonical search path", () => {
  assert.equal(
    v2SearchPath({ NODE_ENV: "production", NEXT_PUBLIC_FOTTY_V2_ENABLED: "true" }),
    "/search"
  );
});

test("local preview enables canonical search path", () => {
  assert.equal(
    v2SearchPath({
      NODE_ENV: "development",
      NEXT_PUBLIC_FOTTY_PREVIEW_ROUTES_ENABLED: "true",
    }),
    "/search"
  );
});

test("legacy /next routes map to canonical paths", () => {
  assert.equal(v2CanonicalFromNextPath("/next/search"), "/search");
  assert.equal(v2CanonicalFromNextPath("/next"), "/");
});
