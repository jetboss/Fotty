import assert from "node:assert/strict";
import test from "node:test";
import { buildWatchPageHref, WATCH_ROUTE_SEGMENT } from "./watch-route.ts";

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
    resolveWatchRouteId("index", new URLSearchParams("id=chelsea-brighton")),
    "chelsea-brighton"
  );
  assert.equal(resolveWatchRouteId("chelsea-brighton", null), "chelsea-brighton");
});

test("buildWatchPageHref always uses the static export segment", () => {
  assert.equal(WATCH_ROUTE_SEGMENT, "index");
  assert.equal(
    buildWatchPageHref(new URLSearchParams({ id: "ppv-event-03", playback: "event" })),
    "/watch/index?id=ppv-event-03&playback=event"
  );
  assert.equal(buildWatchPageHref(new URLSearchParams()), "/watch/index");
});
