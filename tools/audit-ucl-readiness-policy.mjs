import { PROBED_ORIGINS, streamRequest } from "./playback-probe.mjs";

export function currentFixtureSources(snapshot, match, now) {
  const fixtureID = "sports-fixture:champions-league:" + match.id;
  const rows = new Map(snapshot.broadcasts.map((row) => [row.id, row]));
  const descriptors = new Map(), deviceStations = new Set();
  const participants = [match.homeTeam.name, match.awayTeam.name];
  for (const link of snapshot.links) {
    const f = link.fixtureFingerprint;
    if (link.fixtureID !== fixtureID || f?.fixtureID !== fixtureID || f.sport !== "football"
      || f.competitionID !== "champions-league" || Date.parse(f.start) !== Date.parse(match.utcDate)
      || !Array.isArray(f.participants) || f.participants.length !== 2
      || !participants.every((name, side) => name === f.participants[side])
      || link.state !== "listed" || !(Date.parse(link.expiresAt) > now)) continue;
    const row = rows.get(link.broadcastID);
    if (!row || row.kind !== "event" || row.sport !== "football" || row.providerCode !== link.providerCode
      || !(Date.parse(row.expiresAt) > now)) continue;
    if (row.providerCode === "reviewedtv") {
      if (row.channelID) deviceStations.add(row.channelID);
      continue;
    }
    if (!Object.hasOwn(PROBED_ORIGINS, row.providerCode) || typeof row.streamID !== "string" || !row.streamID.trim() || row.streamID.length > 512) continue;
    const url = new URL("/stream/tv/" + encodeURIComponent(row.streamID) + ".json", PROBED_ORIGINS[row.providerCode]);
    descriptors.set(url.href, row.providerCode);
  }
  return { descriptors, deviceStations };
}

export function hasUsableDescriptor(body) {
  return Array.isArray(body?.streams) && body.streams.some((entry) => streamRequest(entry) !== null);
}
