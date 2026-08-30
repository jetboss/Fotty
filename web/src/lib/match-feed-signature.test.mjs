import assert from "node:assert/strict";
import test from "node:test";
import {
  matchFeedSignature,
  mergeFreshMatchFeed,
} from "./match-feed-signature.ts";

function fixture(overrides = {}) {
  return {
    id: "spain-vs-belgium",
    cid: "spain-vs-belgium",
    title: "Spain vs Belgium",
    kind: "fixture",
    status: "Live",
    startsAt: "2026-07-10T19:00:00.000Z",
    sourceCount: 1,
    ...overrides,
  };
}

test("feed signature changes when a playback source arrives", () => {
  const withoutSource = fixture();
  const withSource = fixture({
    eventSource: { source: "echo", id: "spain-vs-belgium-stream" },
    playbackType: "event",
  });

  assert.notEqual(matchFeedSignature([withoutSource]), matchFeedSignature([withSource]));
});

test("active refresh preserves the last playable event mapping", () => {
  const previous = fixture({
    eventSource: { source: "echo", id: "spain-vs-belgium-stream" },
    playbackType: "event",
    coverage: "direct",
    sourceIds: ["spain-vs-belgium-stream"],
  });
  const [merged] = mergeFreshMatchFeed([previous], [fixture({ coverage: "unavailable" })]);

  assert.deepEqual(merged.eventSource, previous.eventSource);
  assert.equal(merged.playbackType, "event");
  assert.equal(merged.coverage, "direct");
});

test("empty refresh and finished fixtures do not erase or revive playback", () => {
  const previous = fixture({
    eventSource: { source: "echo", id: "spain-vs-belgium-stream" },
  });
  assert.deepEqual(mergeFreshMatchFeed([previous], []), [previous]);

  const [finished] = mergeFreshMatchFeed(
    [previous],
    [fixture({ status: "Finished", eventSource: undefined })]
  );
  assert.equal(finished.eventSource, undefined);
});
