#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  cplFixtureSources,
  resolveCPLManifest,
  validateCPLManifest,
} from "../web/workers/playback/src/cpl-fixture-policy.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = resolve(root, "web/public/data/cpl-2026-fixtures.json");
const update = process.argv.includes("--update");
const checkLive = update || process.argv.includes("--live");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));

validateCPLManifest(manifest);
console.log(`CPL manifest passed structural validation (${manifest.fixtures.length} fixtures, revision ${manifest.revision}).`);

if (checkLive) {
  const requestOptions = { headers: { "User-Agent": "Fotty fixture monitor/1.0" }, signal: AbortSignal.timeout(15_000) };
  const [liveResponse, publishedResponse, correctionResponse] = await Promise.all([
    fetch(cplFixtureSources.live, { ...requestOptions, headers: { ...requestOptions.headers, Accept: "text/html" } }),
    fetch(cplFixtureSources.published, { ...requestOptions, headers: { ...requestOptions.headers, Accept: "text/html" } }),
    fetch(cplFixtureSources.correction, { ...requestOptions, headers: { ...requestOptions.headers, Accept: "application/json" } }),
  ]);
  if (!liveResponse.ok) throw new Error(`Live CPL verification failed with HTTP ${liveResponse.status}.`);
  if (!publishedResponse.ok) throw new Error(`Official CPL schedule failed with HTTP ${publishedResponse.status}.`);
  if (!correctionResponse.ok) throw new Error(`Official CPL correction failed with HTTP ${correctionResponse.status}.`);

  const resolved = resolveCPLManifest({
    fallback: manifest,
    verifierHTML: await liveResponse.text(),
    publishedHTML: await publishedResponse.text(),
    correctionJSON: await correctionResponse.json(),
  });
  for (const change of resolved.reviewedVerifierChanges) {
    console.warn(`Known verifier disagreement (official schedule retained): ${change.message}`);
  }
  if (resolved.authoritativeChanges.length === 0) {
    console.log("Official CPL fixture identity and UTC kickoff audit passed.");
  } else if (!update) {
    for (const change of resolved.authoritativeChanges) console.error(`Official CPL drift: ${change.message}`);
    throw new Error(`${resolved.authoritativeChanges.length} official CPL fixture change(s) need review. Run with --update to prepare the manifest change.`);
  } else {
    await writeFile(manifestPath, `${JSON.stringify(resolved.manifest, null, 2)}\n`);
    for (const change of resolved.authoritativeChanges) console.log(`Updated from official schedule: ${change.message}`);
    console.log(`Prepared reviewed CPL manifest revision ${resolved.manifest.revision}.`);
  }
}
