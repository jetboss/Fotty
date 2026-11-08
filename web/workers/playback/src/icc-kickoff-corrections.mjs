// Human-reviewed publication evidence, not a fallback fixture feed. These
// records authorize only the exact old -> new transition of an existing row.
// ICC's rendered schedule and each canonical match-centre page were checked
// on 2026-10-01. This is authoritative publisher confirmation, not independent
// board corroboration. The complete source collection still owns freshness.
const SERIES = "Women's T20I Tri-Series in Malaysia, 2026";
const NOT_BEFORE = "2026-10-01T18:38:42.869Z";

export const ICC_KICKOFF_CORRECTIONS = Object.freeze([
  Object.freeze({ id: "icc:275298", homeId: "icc:10:1810", homeName: "Indonesia Women",
    awayId: "icc:10:1754", awayName: "Samoa Women", seriesId: "15827", competitionName: SERIES,
    from: "2026-10-04T02:30:00.000Z", to: "2026-10-04T02:00:00.000Z", notBefore: NOT_BEFORE,
    verifiedOn: "2026-10-01", evidenceURL: "https://www.icc-cricket.com/matches/275298/indonesia-vs-samoa" }),
  Object.freeze({ id: "icc:275299", homeId: "icc:10:1638", homeName: "Malaysia Women",
    awayId: "icc:10:1810", awayName: "Indonesia Women", seriesId: "15827", competitionName: SERIES,
    from: "2026-10-06T02:00:00.000Z", to: "2026-10-06T02:30:00.000Z", notBefore: NOT_BEFORE,
    verifiedOn: "2026-10-01", evidenceURL: "https://www.icc-cricket.com/matches/275299/malaysia-vs-indonesia" }),
  Object.freeze({ id: "icc:275300", homeId: "icc:10:1638", homeName: "Malaysia Women",
    awayId: "icc:10:1754", awayName: "Samoa Women", seriesId: "15827", competitionName: SERIES,
    from: "2026-10-07T02:30:00.000Z", to: "2026-10-07T02:00:00.000Z", notBefore: NOT_BEFORE,
    verifiedOn: "2026-10-01", evidenceURL: "https://www.icc-cricket.com/matches/275300/malaysia-vs-samoa" }),
]);

export function hasReviewedICCKickoffCorrection(current, previous, observedAt, now) {
  const correction = ICC_KICKOFF_CORRECTIONS.find((record) => record.id === current.id);
  if (!correction || previous.id !== correction.id || previous.start !== correction.from
    || current.start !== correction.to || current.publisherSeriesId !== correction.seriesId) return false;
  const receipt = Date.parse(observedAt);
  const time = now.getTime();
  if (!Number.isFinite(receipt) || !Number.isFinite(time) || receipt < Date.parse(correction.notBefore)
    || receipt > time || time - receipt > 6 * 3_600_000
    || time >= Math.min(Date.parse(correction.from), Date.parse(correction.to))) return false;
  return [previous, current].every((fixture) => fixture.competitionId === "icc"
    && fixture.competitionName === correction.competitionName && fixture.format === "T20"
    && fixture.status === "scheduled" && fixture.home.id === correction.homeId
    && fixture.home.name === correction.homeName && fixture.away.id === correction.awayId
    && fixture.away.name === correction.awayName
    && fixture.source.name === "ICC"
    && fixture.source.url === `https://www.icc-cricket.com/matches/${correction.id.slice(4)}`)
    && current.source.observedAt === observedAt;
}
