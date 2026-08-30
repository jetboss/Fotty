import assert from "node:assert/strict";
import test from "node:test";

function healthStateFromScore(score) {
  if (score === null || score === undefined) return "unknown";
  if (score >= 90) return "excellent";
  if (score >= 70) return "good";
  if (score >= 50) return "fair";
  if (score >= 25) return "unstable";
  return "offline";
}

function heatTierRank(value) {
  switch (value?.toLowerCase()) {
    case "veryhigh":
      return 0;
    case "high":
      return 1;
    case "medium":
      return 2;
    case "low":
      return 3;
    default:
      return 4;
  }
}

function rankEventStreamGuide(variants) {
  const indexed = variants.map((variant, eventIndex) => ({ variant, eventIndex }));
  const sorted = [...indexed].sort((a, b) => {
    const heatDelta = heatTierRank(a.variant.heatTier) - heatTierRank(b.variant.heatTier);
    if (heatDelta !== 0) return heatDelta;
    if (a.variant.hd !== b.variant.hd) return Number(b.variant.hd) - Number(a.variant.hd);
    return (b.variant.viewers || 0) - (a.variant.viewers || 0);
  });

  const all = sorted.map(({ variant, eventIndex }, rankIndex) => ({
    id: `event-${variant.streamNo}-${eventIndex}`,
    displayName: rankIndex === 0 ? "Best Stream" : `Backup Stream ${rankIndex}`,
    eventIndex,
    status: healthStateFromScore(variant.heatTier === "veryhigh" ? 92 : 60),
  }));

  return {
    recommended: all[0] ?? null,
    backups: all.slice(1),
    all,
  };
}

function pickBackupAfterFailure(guide, failedSourceId, alsoFailedSourceIds) {
  const failed = new Set();
  if (failedSourceId) failed.add(failedSourceId);
  if (alsoFailedSourceIds) {
    for (const id of alsoFailedSourceIds) failed.add(id);
  }
  const candidates = guide.all.filter((source) => !failed.has(source.id) && source.status !== "offline");
  return candidates[0] ?? guide.backups.find((source) => !failed.has(source.id)) ?? null;
}

test("healthStateFromScore maps bands", () => {
  assert.equal(healthStateFromScore(95), "excellent");
  assert.equal(healthStateFromScore(75), "good");
  assert.equal(healthStateFromScore(55), "fair");
  assert.equal(healthStateFromScore(30), "unstable");
  assert.equal(healthStateFromScore(10), "offline");
});

test("rankEventStreamGuide prefers heat tier and keeps event indices", () => {
  const guide = rankEventStreamGuide([
    { streamNo: 2, heatTier: "low", hd: false },
    { streamNo: 1, heatTier: "veryhigh", hd: true, viewers: 1200 },
  ]);

  assert.equal(guide.recommended?.displayName, "Best Stream");
  assert.equal(guide.recommended?.eventIndex, 1);
  assert.ok(guide.backups.length >= 1);
});

test("pickBackupAfterFailure skips failed source", () => {
  const guide = rankEventStreamGuide([
    { streamNo: 1, heatTier: "high", hd: true },
    { streamNo: 2, heatTier: "medium", hd: true },
  ]);
  const backup = pickBackupAfterFailure(guide, guide.recommended?.id);
  assert.notEqual(backup?.id, guide.recommended?.id);
});

test("pickBackupAfterFailure skips all previously failed sources", () => {
  const guide = rankEventStreamGuide([
    { streamNo: 1, heatTier: "high", hd: true },
    { streamNo: 2, heatTier: "medium", hd: true },
  ]);
  const first = guide.recommended?.id;
  const second = pickBackupAfterFailure(guide, first);
  assert.ok(second);
  const exhausted = pickBackupAfterFailure(guide, second.id, new Set([first, second.id]));
  assert.equal(exhausted, null);
});
