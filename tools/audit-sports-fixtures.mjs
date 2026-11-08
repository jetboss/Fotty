#!/usr/bin/env node
import { readFile, writeFile, appendFile } from "node:fs/promises";
import { boundedJSON } from "../web/workers/playback/src/coach-safety.mjs";
import { SPORTS_SOURCES } from "../web/workers/playback/src/sports-fixture-sources.mjs";
import { SPORTS_EVENT_SOURCES } from "../web/workers/playback/src/sports-fixture-event-sources.mjs";
import { auditSportsSnapshot, failedSportsAudit, sportsAuditFindingMessages } from "./audit-sports-fixtures-policy.mjs";
import { sportsFindingKey } from "./audit-sports-fixtures-github.mjs";
import { collectSportsFixtureCrosscheck } from "./sports-fixture-crosscheck.mjs";

const arg = (name, fallback = "") => process.argv.find((value) => value.startsWith(`--${name}=`))?.slice(name.length + 3) || fallback;
const now = Date.parse(arg("at", new Date().toISOString()));
if (!Number.isFinite(now)) throw new Error("Audit clock invalid");
let report;
try {
  let body;
  if (arg("fixture-file")) {
    const text = await readFile(arg("fixture-file"), "utf8");
    if (Buffer.byteLength(text) > 2 * 1024 * 1024) throw new Error("Response too large");
    body = JSON.parse(text);
  } else {
    const base = new URL(process.env.FOTTY_WORKER_BASE_URL || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev");
    if (base.protocol !== "https:" || base.username || base.password) throw new Error("Invalid endpoint");
    const signal = AbortSignal.timeout(15_000);
    const response = await fetch(new URL("/api/sports/fixtures", base), { headers: { Accept: "application/json" }, redirect: "error", signal });
    if (response.status === 404 || response.status === 503) {
      const unavailable = response.status === 503 ? await boundedJSON(response, 2 * 1024 * 1024, signal) : null;
      if (unavailable?.activation === "pending") report = { version: 1, checkedAt: new Date(now).toISOString(), failed: false, actionable: false, activation: "pending", findings: [] };
      else report = failedSportsAudit("endpoint-unavailable", now);
    } else if (!response.ok) report = failedSportsAudit("endpoint-unavailable", now);
    else body = await boundedJSON(response, 2 * 1024 * 1024, signal);
  }
  if (!report) {
    report = auditSportsSnapshot(body, { now, descriptors: [...SPORTS_SOURCES, ...SPORTS_EVENT_SOURCES] });
    // Offline fixtures must remain deterministic and make no network calls.
    // A live crosscheck fetches only covered league-owned primary lanes; it
    // cannot activate an undocumented website feed or use a paid credential.
    if (!arg("fixture-file") && !process.argv.includes("--skip-crosscheck")) {
      report.crosscheck = await collectSportsFixtureCrosscheck(body, { now });
      report.findings.push(...report.crosscheck.findings);
      report.failed = report.findings.length > 0;
      report.actionable = report.findings.some((finding) => finding.actionable);
    }
  }
} catch { report = failedSportsAudit("invalid-contract", now); }
if (arg("output")) await writeFile(arg("output"), `${JSON.stringify(report, null, 2)}\n`);
if (process.env.GITHUB_OUTPUT) await appendFile(process.env.GITHUB_OUTPUT,
  `failed=${report.failed}\nactionable=${report.actionable}\nfinding_codes=${[...new Set(report.findings.map((row) => row.code))].join(",")}\nfinding_keys=${report.findings.map(sportsFindingKey).join(",")}\n`);
console.log(`Sports fixture audit: ${report.activation === "pending" ? "activation pending" : report.failed ? "attention required" : "healthy"}.`);
if (Number.isInteger(report.fixtureCount)) console.log(`${report.fixtureCount} fixtures; ${report.competitionCount} competitions; ${report.liveCount} explicitly live; ${report.unsupportedCount} reviewed source gaps.`);
for (const code of new Set(report.findings.map((finding) => finding.code))) console.log(sportsAuditFindingMessages[code]);
if (report.failed && !process.argv.includes("--report-mode")) process.exitCode = 1;
