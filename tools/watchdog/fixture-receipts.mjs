import { auditSportsSnapshot } from "../audit-sports-fixtures-policy.mjs";
import { auditCricketSnapshot } from "../audit-cricket-fixtures-policy.mjs";
import { SPORTS_SOURCES } from "../../web/workers/playback/src/sports-fixture-sources.mjs";
import { readMetadata } from "./source-probes.mjs";
import { WORKER_ORIGIN, FIXTURE_SCOPES, EXPECTED_VERSIONS } from "./manifest.mjs";

const observation = (source, stage, outcome, failureClass, now, environment, facts = {}) => ({ source, stage, outcome, failureClass,
  environment, observedAt: now, versions: { ...EXPECTED_VERSIONS }, facts });
export function fixtureReceipts(body, { kind, now = Date.now(), environment = "production" } = {}) {
  const report = kind === "sports" ? auditSportsSnapshot(body, { now, descriptors: SPORTS_SOURCES.filter((row) => row.id !== "wnba") })
    : auditCricketSnapshot(body, { now, expectedCompetitionIds: ["cpl", "west-indies", "icc"] });
  const receipts = [];
  // The cricket audit's aggregate findings cannot establish per-cohort recovery.
  // Retain them at service scope instead of borrowing a healthy WI receipt to
  // clear held ICC conflicts. Sports findings explicitly identify their cohort.
  for (const finding of report.findings) {
    const scope = FIXTURE_SCOPES.includes(finding.competitionId) ? `fixtures-${finding.competitionId}` : "fixtures-service";
    receipts.push(observation(scope, "integrity", "failure", finding.code, now, environment, { scope: kind }));
  }
  for (const row of body.coverage) {
    if (!FIXTURE_SCOPES.includes(row.competitionId)) continue;
    const outcome = ["unsupported", "offseason"].includes(row.status) ? "inactive"
      : row.status !== "covered" || report.findings.some((finding) => !finding.competitionId || finding.competitionId === row.competitionId)
        ? "unknown" : "success";
    receipts.push(observation(`fixtures-${row.competitionId}`, "integrity", outcome, "accepted-snapshot", now, environment, { scope: kind }));
  }
  if (!report.failed) receipts.push(observation("fixtures-service", "integrity", "success", "accepted-snapshot", now, environment, { scope: kind }));
  return receipts;
}

export async function collectFixtureReceipts({ request = fetch, now = Date.now(), environment = "production" } = {}) {
  const results = [];
  let healthBody;
  try {
    const health = await readMetadata(new URL("/health", WORKER_ORIGIN), { request, maxBytes: 128 * 1024 });
    const body = health.failure ? null : JSON.parse(health.text);
    healthBody = body;
    const matches = body?.service === "fotty-playback" && body.sourceVersion === EXPECTED_VERSIONS.deploymentRevision;
    results.push(observation("worker", "identity", matches ? "success" : "failure", matches ? "metadata-contract" : health.failure || "version-mismatch", now, environment));
    // A different deployment cannot generate a recovery receipt for this one.
    if (!matches) return results;
  } catch { return [observation("worker", "identity", "failure", "invalid-contract", now, environment)]; }
  for (const [kind, path] of [["sports", "/api/sports/fixtures"], ["cricket", "/api/cricket/fixtures"]]) {
    if (kind === "sports" && healthBody.sportsFixtureServiceEnabled !== true
      || kind === "cricket" && healthBody.cricketFixtureRegistryConfigured !== true) {
      results.push(observation("fixtures-service", "integrity", "inactive", "activation-pending", now, environment, { scope: kind }));
      continue;
    }
    try {
      const read = await readMetadata(new URL(path, WORKER_ORIGIN), { request, maxBytes: 2 * 1024 * 1024 });
      if (read.failure) { results.push(observation("fixtures-service", "integrity", "failure", read.failure, now, environment, { scope: kind })); continue; }
      const body = JSON.parse(read.text);
      if (body.activation === "pending") { results.push(observation("fixtures-service", "integrity", "inactive", "activation-pending", now, environment, { scope: kind })); continue; }
      results.push(...fixtureReceipts(body, { kind, now, environment }));
    } catch { results.push(observation("fixtures-service", "integrity", "failure", "invalid-contract", now, environment, { scope: kind })); }
  }
  return results;
}
