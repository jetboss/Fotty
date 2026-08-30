import assert from "node:assert/strict";
import test from "node:test";
import { buildWatchPageHref, WATCH_ROUTE_SEGMENT } from "./watch-route.ts";

/** Keep in sync with watch-session.ts */
function isWatchSessionAuthError(message) {
  const normalized = message?.toLowerCase() || "";
  return /(sign[- ]?in|session expired|refresh access|secure watch|invalid or expired session|sign-in needs to be refreshed)/.test(
    normalized
  );
}

/** Keep in sync with watch-session.ts */
function isP2PContentId(value) {
  return Boolean(value && /^[a-f0-9]{40}$/i.test(value));
}

test("isWatchSessionAuthError detects session expiry copy", () => {
  assert.equal(isWatchSessionAuthError("Your session expired on this device."), true);
  assert.equal(isWatchSessionAuthError("Sign in required to watch live streams."), true);
  assert.equal(isWatchSessionAuthError("Your sign-in needs to be refreshed before this stream can open."), true);
  assert.equal(isWatchSessionAuthError("P2P manifest unavailable"), false);
});

/** Keep in sync with watch-session.ts */
function resolveWatchRouteId(paramsId, searchParams) {
  const fromParams = Array.isArray(paramsId) ? paramsId[0] : paramsId || "";
  if (fromParams && fromParams !== "index" && fromParams !== "placeholder") {
    return fromParams;
  }

  const fromQuery = searchParams?.get("cid") || searchParams?.get("id");
  if (fromQuery && fromQuery !== "index" && fromQuery !== "placeholder") {
    return fromQuery;
  }

  return fromParams;
}

test("resolveWatchRouteId prefers real path/query ids over static export placeholder", () => {
  assert.equal(
    resolveWatchRouteId("index", new URLSearchParams("cid=01dcc1ea3387c2b73953efe3f52286a770737d7c")),
    "01dcc1ea3387c2b73953efe3f52286a770737d7c"
  );
  assert.equal(resolveWatchRouteId("f69b2859510dce33b992dd1940f95254c6e6f51c", null), "f69b2859510dce33b992dd1940f95254c6e6f51c");
});

test("buildWatchPageHref always uses the static export segment", () => {
  assert.equal(WATCH_ROUTE_SEGMENT, "index");
  assert.equal(
    buildWatchPageHref(new URLSearchParams({ id: "ppv-event-03", playback: "event" })),
    "/watch/index?id=ppv-event-03&playback=event"
  );
  assert.equal(
    buildWatchPageHref(
      new URLSearchParams({
        cid: "f69b2859510dce33b992dd1940f95254c6e6f51c",
        playback: "p2p",
        kind: "channel",
      })
    ),
    "/watch/index?cid=f69b2859510dce33b992dd1940f95254c6e6f51c&playback=p2p&kind=channel"
  );
  assert.equal(buildWatchPageHref(new URLSearchParams()), "/watch/index");
});

test("isP2PContentId accepts acestream hashes only", () => {
  assert.equal(isP2PContentId("f69b2859510dce33b992dd1940f95254c6e6f51c"), true);
  assert.equal(isP2PContentId("ppv-sample-event-not-a-hash"), false);
  assert.equal(isP2PContentId(""), false);
  assert.equal(isP2PContentId(null), false);
});
