#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { sportsMonitorIssueBody, sportsMonitorIssueTitle, sportsMonitorIssueMarker, sportsAuditFindingMessages } from "./audit-sports-fixtures-policy.mjs";

const gateName = "Record an unhealthy sports audit";
export function sportsFindingKey(finding) {
  if (!Object.hasOwn(sportsAuditFindingMessages, finding.code) || !/^[a-z0-9-]{1,80}$/.test(finding.competitionId || "service")) throw new Error("Invalid monitor finding");
  const needsEvidence = ["same-upstream-current-omission", "same-upstream-fixture-disagreement"].includes(finding.code);
  if (needsEvidence && !/^[a-f0-9]{64}$/.test(finding.evidenceKey || "")) throw new Error("Invalid comparison identity");
  return `${finding.code}@${finding.competitionId || "service"}${needsEvidence ? `:${finding.evidenceKey}` : ""}`;
}
export function isDedicatedSportsIssue(issue) {
  return issue && !issue.pull_request && issue.title === sportsMonitorIssueTitle && issue.user?.login === "github-actions[bot]"
    && typeof issue.body === "string" && issue.body.includes(sportsMonitorIssueMarker);
}
export function previousSportsFindingKeys(jobs) {
  if (!Array.isArray(jobs)) return [];
  return [...new Set(jobs.flatMap((job) => job.steps || []).filter((step) => step.conclusion === "failure"
    && step.name?.startsWith(`${gateName}: `)).flatMap((step) => step.name.slice(gateName.length + 2).split(","))
    .filter((key) => {
      const [code, scope, extra] = key.split("@");
      const [competitionId, evidenceKey, extraEvidence] = (scope || "").split(":");
      if (extra !== undefined || extraEvidence !== undefined) return false;
      try { return sportsFindingKey({ code, competitionId, evidenceKey }) === key; } catch { return false; }
    }))];
}
export async function reportSportsAuditToGitHub({ report, repository, token, runId, runNumber, branch, request = fetch }) {
  if (!report.failed || report.activation === "pending") return { notified: false, reason: "healthy-or-pending" };
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository) || !/^\d+$/.test(String(runId))
    || !/^\d+$/.test(String(runNumber)) || !token || !branch) throw new Error("Monitor context incomplete");
  const currentKeys = report.findings.map(sportsFindingKey);
  async function api(path, method = "GET", body) {
    const response = await request(`https://api.github.com/repos/${repository}/${path}`, { method,
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Fotty sports fixture monitor/1.0", ...(body ? { "Content-Type": "application/json" } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}), redirect: "error", signal: AbortSignal.timeout(15_000) });
    if (!response.ok) throw new Error("Monitor GitHub request failed");
    return response.json();
  }
  if (!report.actionable) {
    const runs = await api(`actions/workflows/sports-fixtures.yml/runs?status=completed&branch=${encodeURIComponent(branch)}&per_page=10`);
    const preceding = runs.workflow_runs?.filter((run) => String(run.id) !== String(runId) && run.run_number < Number(runNumber))
      .sort((a, b) => b.run_number - a.run_number)[0];
    const previous = preceding ? new Set(previousSportsFindingKeys((await api(`actions/runs/${preceding.id}/jobs?per_page=100`)).jobs)) : new Set();
    if (!currentKeys.some((key) => previous.has(key))) return { notified: false, reason: "awaiting-repeat" };
  }
  const body = sportsMonitorIssueBody(report, `https://github.com/${repository}/actions/runs/${runId}`);
  for (let page = 1; page <= 10; page++) {
    const issues = await api(`issues?state=open&creator=github-actions%5Bbot%5D&per_page=100&page=${page}`);
    if (!Array.isArray(issues)) throw new Error("Monitor issue lookup invalid");
    const issue = issues.filter(isDedicatedSportsIssue).sort((a, b) => a.number - b.number)[0];
    if (issue) { await api(`issues/${issue.number}`, "PATCH", { body }); return { notified: true, reason: "updated", issueNumber: issue.number }; }
    if (issues.length < 100) {
      const created = await api("issues", "POST", { title: sportsMonitorIssueTitle, body });
      return { notified: true, reason: "created", issueNumber: created.number };
    }
  }
  throw new Error("Monitor issue deduplication exhausted");
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const path = process.argv.find((argument) => argument.startsWith("--report="))?.slice(9);
    if (!path) throw new Error("Report path missing");
    const result = await reportSportsAuditToGitHub({ report: JSON.parse(await readFile(path, "utf8")), repository: process.env.GITHUB_REPOSITORY,
      token: process.env.GH_TOKEN, runId: process.env.GITHUB_RUN_ID, runNumber: process.env.GITHUB_RUN_NUMBER, branch: process.env.GITHUB_REF_NAME });
    console.log(`Sports owner alert: ${result.reason}.`);
  } catch { console.error("The sports owner alert could not be recorded. Inspect monitor access and context."); process.exitCode = 1; }
}
