import assert from "node:assert/strict";
import test from "node:test";
import {
  resolveEventBackupIndex,
  shouldArmEmbedLoadTimeout,
  shouldArmEmbedStartTimeout,
} from "./watch-event-recovery.ts";

test("resolveEventBackupIndex advances to next unused feed", () => {
  const guide = {
    all: [
      { id: "a", eventIndex: 0, diagnosticsSafeId: "a" },
      { id: "b", eventIndex: 1, diagnosticsSafeId: "b" },
    ],
  };
  const result = resolveEventBackupIndex(guide, 0, new Set(), (_guide, failedId, alsoFailed) => {
    const failed = new Set(alsoFailed || []);
    if (failedId) failed.add(failedId);
    return guide.all.find((source) => source.id && !failed.has(source.id)) || null;
  });
  assert.equal(result?.nextIndex, 1);
  assert.equal(result?.backup.id, "b");
});

test("embed load timeout only arms with multiple unloaded feeds", () => {
  assert.equal(
    shouldArmEmbedLoadTimeout({
      useEventEmbed: true,
      hasEmbedURL: true,
      frameLoaded: false,
      streamError: null,
      feedCount: 2,
    }),
    true
  );
  assert.equal(
    shouldArmEmbedLoadTimeout({
      useEventEmbed: true,
      hasEmbedURL: true,
      frameLoaded: false,
      streamError: null,
      feedCount: 1,
    }),
    false
  );
});

test("embed start timeout only arms after frame load without playback", () => {
  assert.equal(
    shouldArmEmbedStartTimeout({
      useEventEmbed: true,
      canObservePlayback: true,
      frameLoaded: true,
      feedCount: 2,
      playbackStarted: false,
    }),
    true
  );
  assert.equal(
    shouldArmEmbedStartTimeout({
      useEventEmbed: true,
      canObservePlayback: true,
      frameLoaded: true,
      feedCount: 2,
      playbackStarted: true,
    }),
    false
  );
  assert.equal(
    shouldArmEmbedStartTimeout({
      useEventEmbed: true,
      canObservePlayback: false,
      frameLoaded: true,
      feedCount: 2,
      playbackStarted: false,
    }),
    false,
    "cross-origin embeds must not be abandoned when decoded progress is unobservable"
  );
});
