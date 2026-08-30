import assert from "node:assert/strict";
import test from "node:test";
import {
  classifyPlaybackFault,
  initialPlaybackControllerState,
  isDecodedProgressSample,
  playbackControllerReducer,
  shouldRecoverStalledPlayback,
} from "./playback-controller.ts";

function start(mode = "event", maxRecoveries = 2) {
  return playbackControllerReducer(initialPlaybackControllerState, {
    type: "start-attempt",
    sourceKey: `${mode}:source-a`,
    mode,
    maxRecoveries,
  });
}

test("decoded progress is the only fact that marks playback playing", () => {
  const starting = start();
  const frameReady = playbackControllerReducer(starting, {
    type: "frame-ready",
    attemptId: starting.attemptId,
  });

  assert.equal(frameReady.phase, "frame-ready");
  assert.equal(frameReady.decodedProgressAt, null);

  const playing = playbackControllerReducer(frameReady, {
    type: "decoded-progress",
    attemptId: frameReady.attemptId,
    at: 1234,
  });
  assert.equal(playing.phase, "playing");
  assert.equal(playing.decodedProgressAt, 1234);
});

test("late facts from an older attempt are ignored", () => {
  const first = start();
  const recovering = playbackControllerReducer(first, {
    type: "fault",
    attemptId: first.attemptId,
    fault: classifyPlaybackFault("Playback stalled"),
  });
  const second = playbackControllerReducer(recovering, {
    type: "recovery-committed",
    attemptId: recovering.attemptId,
  });
  const late = playbackControllerReducer(second, {
    type: "decoded-progress",
    attemptId: first.attemptId,
    at: 999,
  });

  assert.equal(late, second);
  assert.equal(late.phase, "starting");
  assert.equal(late.decodedProgressAt, null);
});

test("recovery decisions are mode-specific and bounded", () => {
  const eventAttempt = start("event", 1);
  const eventRecovery = playbackControllerReducer(eventAttempt, {
    type: "fault",
    attemptId: eventAttempt.attemptId,
    fault: classifyPlaybackFault("Feed stopped"),
  });
  assert.equal(eventRecovery.pendingAction, "switch-source");

  const eventRetry = playbackControllerReducer(eventRecovery, {
    type: "recovery-committed",
    attemptId: eventRecovery.attemptId,
  });
  const exhausted = playbackControllerReducer(eventRetry, {
    type: "fault",
    attemptId: eventRetry.attemptId,
    fault: classifyPlaybackFault("Feed stopped again"),
  });
  assert.equal(exhausted.phase, "failed");
  assert.equal(exhausted.pendingAction, "fail");

  const p2pAttempt = start("p2p", 1);
  const p2pRecovery = playbackControllerReducer(p2pAttempt, {
    type: "fault",
    attemptId: p2pAttempt.attemptId,
    fault: classifyPlaybackFault("Network failure"),
  });
  assert.equal(p2pRecovery.pendingAction, "recycle-session");
});

test("auth and entitlement faults never consume recovery budget", () => {
  for (const message of [
    "Your session expired. Sign in again.",
    "A paid Fotty plan is required.",
  ]) {
    const attempt = start("p2p", 3);
    const failed = playbackControllerReducer(attempt, {
      type: "fault",
      attemptId: attempt.attemptId,
      fault: classifyPlaybackFault(message),
    });

    assert.equal(failed.phase, "failed");
    assert.equal(failed.pendingAction, "fail");
    assert.equal(failed.recoveryCount, 0);
  }
});

test("manual source changes advance generation without restoring budget", () => {
  const first = start("event", 2);
  const next = playbackControllerReducer(first, {
    type: "advance-attempt",
    attemptId: first.attemptId,
  });

  assert.equal(next.attemptId, first.attemptId + 1);
  assert.equal(next.recoveryCount, first.recoveryCount);
  assert.equal(next.phase, "starting");
});

test("decoded samples require dimensions and advancing playhead", () => {
  assert.equal(
    isDecodedProgressSample({
      previousTime: 10,
      currentTime: 10,
      readyState: 4,
      videoWidth: 1920,
    }),
    false
  );
  assert.equal(
    isDecodedProgressSample({
      previousTime: 10,
      currentTime: 11,
      readyState: 4,
      videoWidth: 0,
    }),
    false
  );
  assert.equal(
    isDecodedProgressSample({
      previousTime: 10,
      currentTime: 11,
      readyState: 3,
      videoWidth: 1920,
    }),
    true
  );
});

test("shared media watchdog recovers native HLS on low-buffer or hard stalls", () => {
  const base = {
    hasStarted: true,
    isPlaying: true,
    hasError: false,
    playheadStallMs: 14_000,
    hardStallMs: 35_000,
    lowBufferSeconds: 6,
    readyState: 3,
  };

  assert.equal(
    shouldRecoverStalledPlayback({
      ...base,
      stalledMs: 15_000,
      bufferAhead: 2,
    }),
    true
  );
  assert.equal(
    shouldRecoverStalledPlayback({
      ...base,
      stalledMs: 15_000,
      bufferAhead: 20,
    }),
    false
  );
  assert.equal(
    shouldRecoverStalledPlayback({
      ...base,
      stalledMs: 36_000,
      bufferAhead: 20,
    }),
    true
  );
});
