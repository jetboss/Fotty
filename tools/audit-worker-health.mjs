#!/usr/bin/env node

import { WORKER_SOURCE_VERSION } from "../web/workers/playback/src/worker-version.mjs";
import {
  validateWorkerCPL,
  validateWorkerHealth,
} from "./audit-worker-health-policy.mjs";

const baseURL = new URL(process.env.FOTTY_WORKER_BASE_URL
  || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev");
const userAgent = "Fotty Worker contract monitor/1.0";

async function boundedJSON(path, maxBytes) {
  const response = await fetch(new URL(path, baseURL), {
    headers: { Accept: "application/json", "User-Agent": userAgent },
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}.`);
  const length = Number(response.headers.get("content-length"));
  if (Number.isFinite(length) && length > maxBytes) throw new Error(`${path} exceeded ${maxBytes} bytes.`);
  const text = await response.text();
  if (Buffer.byteLength(text) > maxBytes) throw new Error(`${path} exceeded ${maxBytes} bytes.`);
  return { response, body: JSON.parse(text) };
}

function versionHeader(response) {
  return response.headers.get("x-fotty-worker-version");
}

try {
  const healthResponse = await boundedJSON("/health", 128 * 1024);
  const health = validateWorkerHealth({
    body: healthResponse.body,
    headerVersion: versionHeader(healthResponse.response),
    expectedVersion: WORKER_SOURCE_VERSION,
  });

  const cplResponse = await boundedJSON("/api/cricket/cpl-fixtures", 256 * 1024);
  const cpl = validateWorkerCPL({
    body: cplResponse.body,
    sourceHeader: cplResponse.response.headers.get("x-fotty-fixture-source"),
    headerVersion: versionHeader(cplResponse.response),
    expectedVersion: WORKER_SOURCE_VERSION,
  });

  console.log(`Worker ${WORKER_SOURCE_VERSION}: health and CPL contracts passed.`);
  console.log(`CPL: ${cpl.fixtureCount} fixtures, ${cpl.sourceStatus}.`);
  for (const warning of [...health.warnings, ...cpl.warnings]) {
    console.warn(`WARNING: ${warning}`);
  }
  console.log("The quota-consuming /api/football/live route was not called.");
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
