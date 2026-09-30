#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import {
  cricketMonitorIssueBody,
  cricketAuditFindingMessages,
  cricketMonitorIssueMarker,
  cricketMonitorIssueTitle,
  shouldNotifyCricketOwner,
} from "./audit-cricket-fixtures-policy.mjs";

const failureGateName = "Record an unhealthy cricket audit";

export function isDedicatedCricketMonitorIssue(issue) {
  return issue && !issue.pull_request && issue.title === cricketMonitorIssueTitle
    && issue.user?.login === "github-actions[bot]" && typeof issue.body === "string"
    && issue.body.includes(cricketMonitorIssueMarker);
}

// A failed tool install or unrelated step is not evidence of repeated fixture failure.
export function previousRunHadFailedCricketAudit(jobs) {
  return previousRunCricketFailureCodes(jobs).length > 0;
}

export function previousRunCricketFailureCodes(jobs) {
  if (!Array.isArray(jobs)) return [];
  return [...new Set(jobs.flatMap((job) => Array.isArray(job.steps) ? job.steps : [])
    .filter((step) => step.conclusion === "failure" && step.name?.startsWith(`${failureGateName}: `))
    .flatMap((step) => step.name.slice(failureGateName.length + 2).split(","))
    .filter((code) => Object.hasOwn(cricketAuditFindingMessages, code)))];
}

export async function reportCricketAuditToGitHub({ report, repository, token, runId, runNumber, branch, request = fetch }) {
  if (report.failed !== true) return { notified: false, reason: "healthy" };
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)
    || !/^\d+$/.test(String(runId)) || !/^\d+$/.test(String(runNumber)) || !token || !branch) {
    throw new Error("The GitHub monitor context is incomplete.");
  }
  async function api(path, { method = "GET", body } = {}) {
    const response = await request(`https://api.github.com/repos/${repository}/${path}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Fotty cricket fixture monitor/1.0",
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error("The GitHub monitor request failed.");
    return response.json();
  }

  let previousAuditFailed = false;
  if (report.actionable !== true) {
    const history = await api(`actions/workflows/cricket-fixtures.yml/runs?status=completed&branch=${encodeURIComponent(branch)}&per_page=10`);
    const preceding = history.workflow_runs?.filter((run) => String(run.id) !== String(runId)
      && Number.isInteger(run.run_number) && run.run_number < Number(runNumber))
      .sort((left, right) => right.run_number - left.run_number)[0];
    if (preceding) {
      const jobs = await api(`actions/runs/${preceding.id}/jobs?per_page=100`);
      const previousCodes = new Set(previousRunCricketFailureCodes(jobs.jobs));
      previousAuditFailed = report.findings.some((finding) => previousCodes.has(finding.code));
    }
  }
  if (!shouldNotifyCricketOwner(report, { previousAuditFailed })) {
    return { notified: false, reason: "awaiting-repeat" };
  }

  const body = cricketMonitorIssueBody(report, { runURL: `https://github.com/${repository}/actions/runs/${runId}` });
  let dedicatedIssue;
  for (let page = 1; page <= 10; page += 1) {
    const issues = await api(`issues?state=open&creator=github-actions%5Bbot%5D&per_page=100&page=${page}`);
    if (!Array.isArray(issues)) throw new Error("The GitHub issue lookup failed.");
    const matches = issues.filter(isDedicatedCricketMonitorIssue);
    if (matches.length > 0) {
      dedicatedIssue = matches.sort((left, right) => left.number - right.number)[0];
      break;
    }
    if (issues.length < 100) break;
    if (page === 10) throw new Error("The GitHub issue lookup could not establish deduplication.");
  }
  if (dedicatedIssue) {
    await api(`issues/${dedicatedIssue.number}`, { method: "PATCH", body: { body } });
    return { notified: true, reason: "updated", issueNumber: dedicatedIssue.number };
  }
  const issue = await api("issues", { method: "POST", body: { title: cricketMonitorIssueTitle, body } });
  return { notified: true, reason: "created", issueNumber: issue.number };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const reportPath = process.argv.find((argument) => argument.startsWith("--report="))?.slice("--report=".length);
    if (!reportPath) throw new Error("The monitor report path is missing.");
    const report = JSON.parse(await readFile(reportPath, "utf8"));
    const result = await reportCricketAuditToGitHub({
      report,
      repository: process.env.GITHUB_REPOSITORY,
      token: process.env.GH_TOKEN,
      runId: process.env.GITHUB_RUN_ID,
      runNumber: process.env.GITHUB_RUN_NUMBER,
      branch: process.env.GITHUB_REF_NAME,
    });
    console.log(result.notified
      ? `Cricket owner alert ${result.reason} in dedicated issue #${result.issueNumber}.`
      : `Cricket owner alert: ${result.reason}.`);
  } catch {
    console.error("The cricket owner alert could not be recorded. Inspect the monitor context and GitHub access.");
    process.exitCode = 1;
  }
}
