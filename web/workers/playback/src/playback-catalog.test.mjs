import assert from "node:assert/strict";
import test from "node:test";

import worker from "./index.js";

// The legacy website stream catalog and embed redirect were retired: the iOS
// app reads /api/live/catalog and /api/live/broadcasts. The old paths must not
// reach any upstream provider.
for (const path of [
  "/api/live/streams?source=delta&id=match",
  "/api/embed/player?source=alpha&id=fotty-worker-health-probe&streamNo=1",
]) {
  test(`retired route ${path.split("?")[0]} returns 404 without an upstream request`, async (t) => {
    const upstream = t.mock.method(globalThis, "fetch", async () => {
      throw new Error("A retired route must not fetch a provider");
    });
    const response = await worker.fetch(new Request(`https://test.invalid${path}`), {});
    assert.equal(response.status, 404);
    assert.equal(response.headers.get("location"), null);
    assert.equal(upstream.mock.callCount(), 0);
  });
}
