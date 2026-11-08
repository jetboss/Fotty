#!/usr/bin/env node

import { appendFile, readFile, writeFile } from "node:fs/promises";
import { auditCricketSnapshot, auditUnavailableCricketService, cricketAuditFindingMessages, failedCricketAudit } from "./audit-cricket-fixtures-policy.mjs";
import { auditIndependentCricketCoverage, parseIndependentCWIInternationalFixtures } from "./audit-cricket-fixtures-independent.mjs";
import { CRICKET_COMPETITIONS } from "../web/workers/playback/src/cricket-fixture-policy.mjs";

const valueFor = (name, fallback) => {
  const prefix = `--${name}=`;
  return process.argv.find((argument) => argument.startsWith(prefix))?.slice(prefix.length) ?? fallback;
};
const now = Date.parse(valueFor("at", new Date().toISOString()));
if (!Number.isFinite(now)) throw new Error("--at must be a valid timestamp.");
const fixtureFile = valueFor("fixture-file", "");
const independentFile = valueFor("independent-file", "");
const outputFile = valueFor("output", "");
const reportMode = process.argv.includes("--report-mode");
const expectedCompetitionIds = CRICKET_COMPETITIONS.map((competition) => competition.id);
const maxBytes = 1024 * 1024;

async function fetchBoundedText(url, accept = "application/json") {
  let response;
  try {
    response = await fetch(url, {
      headers: { Accept: accept, "User-Agent": "Fotty cricket fixture monitor/1.0" },
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    return { failure: "endpoint-unavailable" };
  }
  if (!response.body) return { failure: "endpoint-unavailable" };
  const reader = response.body.getReader();
  const chunks = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel();
        return { failure: "response-too-large" };
      }
      chunks.push(value);
    }
  } catch {
    return { failure: "endpoint-unavailable" };
  } finally {
    reader.releaseLock();
  }
  return { text: Buffer.concat(chunks).toString("utf8"), status: response.status };
}

async function fetchSnapshot() {
  const baseURL = new URL(process.env.FOTTY_WORKER_BASE_URL || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev");
  if (baseURL.protocol !== "https:" || baseURL.username || baseURL.password) return { failure: "endpoint-unavailable" };
  const result = await fetchBoundedText(new URL("/api/cricket/fixtures", baseURL));
  if (result.failure) return result;
  if (result.status !== 200 && result.status !== 503) return { failure: "endpoint-unavailable" };
  try {
    const body = JSON.parse(result.text);
    return result.status === 503 ? { unavailableBody: body } : { body };
  } catch {
    return { failure: result.status === 503 ? "endpoint-unavailable" : "invalid-json" };
  }
}

async function independentSchedule() {
  if (fixtureFile && !independentFile) return { requested: false };
  try {
    const result = independentFile
      ? { text: await readFile(independentFile, "utf8") }
      : await fetchBoundedText(new URL("https://www.windiescricket.com/fixtures/class_type/international/"), "text/html");
    if (result.failure || (result.status && result.status !== 200)) return { requested: true, unavailable: true };
    return { requested: true, fixtures: parseIndependentCWIInternationalFixtures(result.text) };
  } catch {
    return { requested: true, unavailable: true };
  }
}

let report;
try {
  const [result, independent] = await Promise.all([
    fixtureFile ? readFile(fixtureFile, "utf8").then((text) => Buffer.byteLength(text) > maxBytes
      ? { failure: "response-too-large" } : { body: JSON.parse(text) }) : fetchSnapshot(),
    independentSchedule(),
  ]);
  report = result.unavailableBody ? auditUnavailableCricketService(result.unavailableBody, { now }) : result.failure
    ? failedCricketAudit(result.failure, now)
    : auditCricketSnapshot(result.body, { now, expectedCompetitionIds });
  if (independent.unavailable) {
    report.findings.push({ code: "independent-check-unavailable", actionable: false });
    report.failed = true;
    report.independentCheck = "unavailable";
  } else if (independent.requested && result.body) {
    const comparison = auditIndependentCricketCoverage(result.body, independent.fixtures, { now });
    report.findings.push(...comparison.findings);
    report.failed ||= comparison.findings.length > 0;
    report.actionable ||= comparison.findings.some((finding) => finding.actionable);
    report.independentCheck = "verified";
    report.independentCurrentCount = comparison.expectedCurrentCount;
    report.independentMatchedCount = comparison.matchedCurrentCount;
  } else {
    report.independentCheck = independent.requested ? "not-compared" : "not-requested";
  }
} catch {
  // No upstream body, URL, query string or exception message enters logs or owner issues.
  report = failedCricketAudit("invalid-contract", now);
}

if (outputFile) await writeFile(outputFile, `${JSON.stringify(report, null, 2)}\n`);
if (process.env.GITHUB_OUTPUT) {
  await appendFile(process.env.GITHUB_OUTPUT, `failed=${report.failed}\nactionable=${report.actionable}\nfinding_codes=${report.findings.map((finding) => finding.code).join(",")}\n`);
}
console.log(`Cricket fixture audit: ${report.failed ? "attention required" : "healthy"}.`);
if (Number.isInteger(report.fixtureCount)) {
  console.log(`Validated ${report.fixtureCount} fixtures across ${report.competitionCount} competitions; ${report.activeWindowCount} current/imminent windows.`);
}
for (const finding of report.findings) console.log(cricketAuditFindingMessages[finding.code]);
if (report.failed && !reportMode) process.exitCode = 1;
