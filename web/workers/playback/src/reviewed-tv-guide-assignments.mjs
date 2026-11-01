import { currentReviewedTVGuide } from "./reviewed-tv-guide.mjs";
import { associateBroadcasts, broadcastRegistryHash } from "./broadcast-registry-policy.mjs";
// New guide-driven match associations are derived on read, never persisted into
// the established accepted-record store. Older binaries and rollback keep it intact.
export async function reviewedTVGuideAssignments(guide, fixtures, now) {
  const clock = +new Date(now), broadcasts = [];
  const competitions = {baseball:{id:"mlb",label:"MLB"},hockey:{id:"nhl",label:"NHL"}};
  for (const row of currentReviewedTVGuide(guide, now)) {
    const competition = competitions[row.sport];
    if (!competition || clock - Date.parse(row.observedAt) > 600_000
      || /\b(?:repetici[oó]n|replay|highlights|resumen|si es necesario|if necessary|game\s*#?\d|juego\s*#?\d)\b/iu.test(row.title)) continue;
    const pair = new RegExp("^"+competition.label+" (?:[–−-] .+ )?[–−-] (.+?) vs\\. (.+)$","u").exec(row.title);
    if (!pair || pair[1] === pair[2]) continue;
    const samePair = (f) => f.sport === row.sport && f.competitionID === competition.id
      && f.start?.slice(0,10) === row.start.slice(0,10)
      && [pair[1],pair[2]].every((name) => f.participants.some((p) => p.normalize("NFKC").toLowerCase() === name.normalize("NFKC").toLowerCase()));
    if (fixtures.filter(samePair).length !== 1) continue; // Same-day doubleheaders need additional explicit identity.
    const fixture = fixtures.find(samePair);
    if (!fixture.verified || !["scheduled","live"].includes(fixture.status) || fixture.squad?.gender !== "men" || fixture.squad?.ageGroup !== "senior"
      || !Number.isFinite(Date.parse(fixture.observedAt)) || Math.abs(clock-Date.parse(fixture.observedAt)) > 600_000
      || Date.parse(fixture.start)-Date.parse(row.start) < 0 || Date.parse(fixture.start)-Date.parse(row.start) > 3600_000) continue;
    const providerEventID="reviewed-tv:assignment:"+row.id.slice("tv-guide:".length);
    broadcasts.push({ id:"br:"+await broadcastRegistryHash(["reviewedtv",providerEventID,"reviewed-tv:"+row.channelID.slice("sports-channel:".length)]),
      providerCode:"reviewedtv",providerEventID,streamID:"reviewed-tv:"+row.channelID.slice("sports-channel:".length),resourceType:"tv",
      scope:row.sport,kind:"event",sport:row.sport,title:row.title,participants:[pair[1],pair[2]],start:row.start,
      competitionID:competition.id,squad:fixture.squad,channelID:row.channelID,stationMarket:"UY",verification:"dated",issues:[],observedAt:row.observedAt,
      expiresAt:new Date(Math.min(Date.parse(row.expiresAt),Date.parse(row.observedAt)+600_000)).toISOString() });
  }
  const providers=[...new Set(broadcasts.map(r=>r.scope))].map(scope=>({providerCode:"reviewedtv",scope,status:"partial",complete:false,
    observedAt:new Date(Math.min(...broadcasts.filter(r=>r.scope===scope).map(r=>Date.parse(r.observedAt)))).toISOString(),
    expiresAt:new Date(Math.min(...broadcasts.filter(r=>r.scope===scope).map(r=>Date.parse(r.expiresAt)))).toISOString()}));
  return {providers,broadcasts,links:associateBroadcasts({fixtures,broadcasts,providers,now:new Date(now)})};
}
