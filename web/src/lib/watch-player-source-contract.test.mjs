import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const playerSource = readFileSync(
  new URL("../components/watch/WatchPlayers.tsx", import.meta.url),
  "utf8"
);
const toolbarSource = readFileSync(
  new URL("../components/watch/WatchToolbarV2.tsx", import.meta.url),
  "utf8"
);

test("iframe load is frame readiness, not decoded playback", () => {
  const loadHandler = playerSource.match(/onLoad=\{\(\) => \{([\s\S]*?)\n\s*\}\}/)?.[1] ?? "";
  assert.match(loadHandler, /onFrameLoad/);
  assert.doesNotMatch(loadHandler, /onPlaybackStarted|onPlaybackPulse/);
});

test("one iframe error cannot fire two source-switch callbacks", () => {
  const errorHandler = playerSource.match(/onError=\{\(\) => \{([\s\S]*?)\n\s*\}\}/)?.[1] ?? "";
  assert.equal((errorHandler.match(/onFrameError/g) || []).length, 1);
  assert.doesNotMatch(errorHandler, /onTryNextFeed/);
});

test("web watch exposes no provider new-tab escape", () => {
  assert.doesNotMatch(playerSource, /Open feed in new tab|openFeedURL/);
  assert.doesNotMatch(toolbarSource, /Open feed in new tab|openFeedHref|target=["']_blank/);
});
