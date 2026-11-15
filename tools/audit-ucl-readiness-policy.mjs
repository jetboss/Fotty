export const supportedUCLSourceCodes = Object.freeze([
  "admin",
  "delta",
  "echo",
  "golf",
  "hotel",
  "india",
  "alpha",
]);

// A fixture is ready when the cloud registry lists at least one current link
// for its exact official identity. Ambiguous, conflicting or expired links do
// not count; this is metadata readiness, not decoded-playback proof.
export function listedRegistryLinkCount(snapshot, fixtureID) {
  if (!snapshot || !Array.isArray(snapshot.links)) return 0;
  return new Set(snapshot.links
    .filter((link) => link && link.fixtureID === fixtureID && link.state === "listed")
    .map((link) => link.broadcastID)).size;
}
