import assert from "node:assert/strict";
import test from "node:test";
import { buildEmbedPlaybackInjection } from "./embed-player-proxy.ts";

test("embed bridge requires decoded playhead progress before reporting success", () => {
  const injection = buildEmbedPlaybackInjection("https://provider.example");

  assert.match(injection, /currentTime <= previousTime \+ 0\.05/);
  assert.match(injection, /video\.videoWidth <= 0/);
  assert.match(injection, /video\.addEventListener\("timeupdate"/);
  assert.doesNotMatch(
    injection,
    /video\.addEventListener\("playing"[\s\S]{0,160}emitPlayback\("started"\)/
  );
});
