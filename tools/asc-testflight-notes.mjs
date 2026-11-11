#!/usr/bin/env node
// Finds a TestFlight build with an App Store Connect API key and, unless
// --check is given, sets its "What to Test" note (API field whatsNew; this
// app's notes use the en-GB localization).
//
//   node tools/asc-testflight-notes.mjs --bundle-id com.jelani.Fotty \
//     --version 3.0.0 --build 276 [--notes "Bug fixes"] [--group "Fotty Internal Smoke"]
//     [--check] [--wait 1800]
//
// --group adds the build to that TestFlight group after the note is set, which
// emails and notifies its testers (the group does not take new builds
// automatically).
//
// Uses the same variables as owner-tools/testflight-usage-sync:
// APP_STORE_CONNECT_ISSUER_ID (required), APP_STORE_CONNECT_KEY_ID and
// APP_STORE_CONNECT_PRIVATE_KEY_PATH (both optional when exactly one
// AuthKey_*.p8 is in ~/.appstoreconnect/private_keys). tools/testflight-upload.sh
// loads them from the gitignored .env.asc.local. The private key only signs a
// short-lived token; it is never printed or logged.
import { createPrivateKey, sign } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const API = "https://api.appstoreconnect.apple.com/v1";
const KEY_DIR = path.join(homedir(), ".appstoreconnect", "private_keys");

function fail(message) {
  console.error(`asc-testflight-notes: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const options = { check: false, wait: 0 };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === "--check") { options.check = true; continue; }
    const value = argv[i + 1];
    if (value === undefined) fail(`${flag} needs a value`);
    i += 1;
    if (flag === "--bundle-id") options.bundleId = value;
    else if (flag === "--version") options.version = value;
    else if (flag === "--build") options.build = value;
    else if (flag === "--notes") options.notes = value;
    else if (flag === "--wait") options.wait = Number(value);
    else if (flag === "--group") options.group = value;
    else fail(`unknown option ${flag}`);
  }
  if (!options.bundleId || !options.version || !options.build) fail("--bundle-id, --version and --build are required");
  if (!/^\d+(\.\d+){0,2}$/.test(options.version) || !/^\d+$/.test(options.build)) fail("version or build is malformed");
  if (!options.check && !options.notes) fail("give --notes, or --check for a read-only lookup");
  if (options.notes && options.notes.length > 4000) fail("notes are longer than 4,000 characters");
  if (!Number.isInteger(options.wait) || options.wait < 0 || options.wait > 7200) fail("--wait must be 0–7200 seconds");
  return options;
}

export function keyPath(env = process.env, directory = KEY_DIR) {
  const explicit = env.APP_STORE_CONNECT_PRIVATE_KEY_PATH?.trim();
  if (explicit) {
    const name = path.basename(explicit);
    if (!/^AuthKey_[A-Z0-9]+\.p8$/.test(name)) fail("APP_STORE_CONNECT_PRIVATE_KEY_PATH must name an AuthKey_<KEY_ID>.p8 file");
    directory = path.dirname(explicit);
    env = { ...env, APP_STORE_CONNECT_KEY_ID: env.APP_STORE_CONNECT_KEY_ID?.trim() || name.slice(8, -3) };
  }
  let keyID = env.APP_STORE_CONNECT_KEY_ID?.trim();
  if (!keyID) {
    const keys = readdirSync(directory).filter((name) => /^AuthKey_[A-Z0-9]+\.p8$/.test(name));
    if (keys.length !== 1) fail(`set APP_STORE_CONNECT_KEY_ID: found ${keys.length} AuthKey_*.p8 files in ${directory}`);
    keyID = keys[0].slice("AuthKey_".length, -".p8".length);
  }
  if (!/^[A-Z0-9]{8,20}$/.test(keyID)) fail("APP_STORE_CONNECT_KEY_ID is malformed");
  const file = path.join(directory, `AuthKey_${keyID}.p8`);
  const info = statSync(file, { throwIfNoEntry: false });
  if (!info?.isFile()) fail(`no key file for APP_STORE_CONNECT_KEY_ID in ${directory}`);
  if ((info.mode & 0o077) !== 0) fail(`${path.basename(file)} must be readable only by you (chmod 600)`);
  return { keyID, file };
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

export function token({ keyID, file, issuerID, now = Math.floor(Date.now() / 1000) }) {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID, typ: "JWT" }));
  const payload = base64url(JSON.stringify({ iss: issuerID, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" }));
  const key = createPrivateKey(readFileSync(file));
  const signature = sign("sha256", Buffer.from(`${header}.${payload}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${signature.toString("base64url")}`;
}

async function request(auth, method, route, body) {
  const response = await fetch(`${API}${route}`, {
    method,
    headers: { Authorization: `Bearer ${auth}`, ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (!response.ok) {
    let detail = text.slice(0, 300);
    try { detail = JSON.parse(text).errors?.map((e) => e.detail ?? e.title).join("; ") ?? detail; } catch {}
    fail(`${method} ${route.split("?")[0]} returned ${response.status}: ${detail}`);
  }
  return text ? JSON.parse(text) : {};
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const issuerID = process.env.APP_STORE_CONNECT_ISSUER_ID?.trim();
  if (!issuerID || !/^[0-9a-f-]{36}$/i.test(issuerID)) fail("APP_STORE_CONNECT_ISSUER_ID is missing or malformed (see .env.asc.local)");
  const key = keyPath();
  const auth = () => token({ ...key, issuerID });

  const apps = await request(auth(), "GET", `/apps?filter[bundleId]=${encodeURIComponent(options.bundleId)}&limit=1`);
  const app = apps.data?.[0];
  if (!app) fail(`no app with bundle ID ${options.bundleId}`);

  const deadline = Date.now() + options.wait * 1000;
  let build;
  for (;;) {
    const builds = await request(auth(), "GET",
      `/builds?filter[app]=${app.id}&filter[version]=${options.build}`
      + `&filter[preReleaseVersion.version]=${encodeURIComponent(options.version)}&limit=1`);
    build = builds.data?.[0];
    const state = build?.attributes?.processingState;
    if (state === "VALID" || state === "FAILED" || state === "INVALID" || Date.now() >= deadline) break;
    console.log(`Build ${options.version} (${options.build}): ${state ?? "not listed yet"}; checking again in 60 s`);
    await sleep(60_000);
  }
  if (!build) fail(`build ${options.version} (${options.build}) is not listed yet`);
  const state = build.attributes.processingState;
  const localizations = await request(auth(), "GET", `/builds/${build.id}/betaBuildLocalizations?limit=50`);
  const english = localizations.data?.find((item) => item.attributes?.locale === "en-GB")
    ?? localizations.data?.find((item) => item.attributes?.locale?.startsWith("en"));
  console.log(`Build ${options.version} (${options.build}): ${state}; What to Test: ${JSON.stringify(english?.attributes?.whatsNew ?? null)}`);
  if (options.check) return;
  if (state !== "VALID") fail(`build is ${state}; the note can be set once processing finishes`);

  if (english) {
    await request(auth(), "PATCH", `/betaBuildLocalizations/${english.id}`, {
      data: { type: "betaBuildLocalizations", id: english.id, attributes: { whatsNew: options.notes } },
    });
  } else {
    await request(auth(), "POST", "/betaBuildLocalizations", {
      data: {
        type: "betaBuildLocalizations",
        attributes: { locale: "en-GB", whatsNew: options.notes },
        relationships: { build: { data: { type: "builds", id: build.id } } },
      },
    });
  }
  console.log(`Set What to Test for ${options.version} (${options.build}).`);

  if (options.group) {
    const groups = await request(auth(), "GET", `/apps/${app.id}/betaGroups?limit=50`);
    const group = groups.data?.find((item) => item.attributes?.name === options.group);
    if (!group) fail(`no TestFlight group named ${JSON.stringify(options.group)}`);
    await request(auth(), "POST", `/betaGroups/${group.id}/relationships/builds`, {
      data: [{ type: "builds", id: build.id }],
    });
    console.log(`Added ${options.version} (${options.build}) to ${options.group}; its testers are notified.`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => fail(error.message));
}
