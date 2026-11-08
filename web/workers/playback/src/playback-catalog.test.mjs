import assert from "node:assert/strict";
import test from "node:test";

import worker from "./index.js";
import { WORKER_SOURCE_VERSION } from "./worker-version.mjs";

test("stream catalog drops unreviewed, insecure, and credentialed embed origins", async (t) => {
  t.mock.method(globalThis, "fetch", async () => Response.json([
    { source: "delta", streamNo: 1, embedUrl: "http://embed.st/embed/delta/match/1" },
    { source: "delta", streamNo: 2, embedUrl: "https://embed.st.evil.example/player" },
    { source: "delta", streamNo: 3, embedUrl: "https://user:password@embed.st/player" },
    { source: "delta", streamNo: 4, embedUrl: "https://unknown.example/player" },
  ]));

  const response = await worker.fetch(new Request(
    "https://test.invalid/api/live/streams?source=delta&id=match"
  ), {});
  assert.equal(response.status, 200);
  const variants = await response.json();
  assert.equal(variants.length, 1, "the bounded legacy fallback should be the only admitted result");
  assert.equal(new URL(variants[0].embedUrl).hostname, "embed.st");
  assert.equal(new URL(variants[0].embedUrl).protocol, "https:");
});

test("stream catalog keeps reviewed HTTPS provider subdomains", async (t) => {
  t.mock.method(globalThis, "fetch", async () => Response.json([
    { source: "delta", streamNo: 1, embedUrl: "https://video.embed.st/embed/delta/match/1" },
  ]));
  const response = await worker.fetch(new Request(
    "https://test.invalid/api/live/streams?source=delta&id=match"
  ), {});
  const variants = await response.json();
  assert.equal(variants.length, 1);
  assert.equal(variants[0].embedUrl, "https://video.embed.st/embed/delta/match/1");
});

test("stream catalog reports partial upstream coverage without discarding a playable result", async (t) => {
  t.mock.method(globalThis, "fetch", async (input) => {
    const host = new URL(String(input)).hostname;
    if (host === "www.streamex.net") return Response.json([
      { source: "delta", streamNo: 1, embedUrl: "https://video.embed.st/embed/delta/match/1" },
    ]);
    if (host === "streamex.sh") return new Response("unavailable", { status: 503 });
    throw new TypeError("network unavailable");
  });

  const response = await worker.fetch(new Request(
    "https://test.invalid/api/live/streams?source=delta&id=match"
  ), {});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Fotty-Catalog-Coverage"), "partial");
  assert.equal(response.headers.get("X-Fotty-Catalog-Responding"), "1");
  assert.equal(response.headers.get("X-Fotty-Catalog-Attempted"), "3");
  const variants = await response.json();
  assert.equal(variants.length, 1);
  assert.equal(variants[0].provider, "StreameX");
});

test("stream catalog identifies fallback-only coverage while preserving the direct attempt", async (t) => {
  t.mock.method(globalThis, "fetch", async () => {
    throw new TypeError("network unavailable");
  });
  const response = await worker.fetch(new Request(
    "https://test.invalid/api/live/streams?source=delta&id=match"
  ), {});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Fotty-Catalog-Coverage"), "fallback-only");
  assert.equal(response.headers.get("X-Fotty-Catalog-Responding"), "0");
  const variants = await response.json();
  assert.equal(variants.length, 1);
  assert.equal(variants[0].provider, "Legacy");
  assert.equal(variants[0].embedUrl, "https://embed.st/embed/delta/match/1");
});

test("embed redirect preserves source identity and production version evidence", async () => {
  const response = await worker.fetch(new Request(
    "https://test.invalid/api/embed/player?source=alpha&id=fotty-worker-health-probe&streamNo=1"
  ), {});
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://embed.st/embed/alpha/fotty-worker-health-probe/1",
  );
  assert.equal(response.headers.get("x-fotty-worker-version"), WORKER_SOURCE_VERSION);
});
