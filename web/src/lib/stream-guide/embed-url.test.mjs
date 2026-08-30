import test from "node:test";
import assert from "node:assert/strict";
import {
  buildDirectEmbedUrl,
  firstPlayableEventStream,
  synthesizeEventStreamVariants,
} from "./embed-url.ts";

test("buildDirectEmbedUrl uses embed.st path", () => {
  assert.equal(
    buildDirectEmbedUrl("echo", "sample-event-game-251515", 2),
    "https://embed.st/embed/echo/sample-event-game-251515/2"
  );
});

test("synthesizeEventStreamVariants creates numbered feeds", () => {
  const streams = synthesizeEventStreamVariants("echo", "sample-event", 2);
  assert.equal(streams.length, 2);
  assert.equal(streams[0]?.streamNo, 1);
  assert.equal(streams[1]?.streamNo, 2);
  assert.equal(streams[0]?.heatTier, "synthesized");
  assert.ok(streams.every((stream) => stream.embedUrl.includes("/embed/echo/")));
});

test("firstPlayableEventStream skips empty embed urls", () => {
  const stream = firstPlayableEventStream([
    { id: "a", source: "echo", streamNo: 1, embedUrl: "" },
    { id: "a", source: "echo", streamNo: 2, embedUrl: "https://embed.st/embed/echo/a/2" },
  ]);
  assert.equal(stream?.streamNo, 2);
});
