#!/usr/bin/env node
// Read-only integrity/coherence checks. No capture, network, approval or release authority.
import { createHash } from "node:crypto";
import { lstat, readFile, realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pngDimensions } from "./review-visual-baselines.mjs";

export const screenIDs = Object.freeze(["home", "matchday", "search", "settings", "match-details", "single-player"]);
const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };
const string = (value, label, maximum = 1000) => requireValue(typeof value === "string"
  && value.trim().length > 0 && value.length <= maximum && !/[\x00-\x1f\x7f]/.test(value), `Invalid ${label}`);
const digest = (value, label) => requireValue(typeof value === "string" && /^[a-f0-9]{64}$/.test(value), `Invalid ${label} SHA-256`);
const object = (value, keys, label) => requireValue(value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).every((key) => keys.includes(key)), `Invalid or unknown ${label} fields`);
const list = (value, minimum, maximum, label) => requireValue(Array.isArray(value)
  && value.length >= minimum && value.length <= maximum, `Invalid ${label} count`);
function uniqueID(value, seen, label) {
  requireValue(typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(value), `Invalid ${label} ID`);
  requireValue(!seen.has(value), `Duplicate ${label} ID: ${value}`); seen.add(value);
}
function relativeFile(value, label) {
  string(value, label, 500);
  requireValue(!path.isAbsolute(value) && !value.includes("\\")
    && value.split("/").every((part) => part && part !== "." && part !== ".." && part !== ".git"), `Unsafe ${label} path`);
  return value;
}
async function directory(value, label) {
  string(value, label, 2000);
  const resolved = path.resolve(value);
  try {
    const entry = await lstat(resolved);
    requireValue(entry.isDirectory() && !entry.isSymbolicLink() && await realpath(resolved) === resolved,
      `Unsafe ${label} directory`);
  } catch { throw new Error(`Missing or symlinked ${label} directory`); }
  return resolved;
}
async function regularFile(root, relative, maximum, label) {
  relativeFile(relative, label);
  let current = root;
  const parts = relative.split("/");
  try {
    for (let index = 0; index < parts.length; index += 1) {
      current = path.join(current, parts[index]);
      const entry = await lstat(current);
      requireValue(!entry.isSymbolicLink(), `Symlink in ${label}`);
      requireValue(index === parts.length - 1 ? entry.isFile() && entry.size > 0 && entry.size <= maximum
        : entry.isDirectory(), `Invalid ${label}`);
    }
    const bytes = await readFile(current);
    requireValue(bytes.length > 0 && bytes.length <= maximum, `Oversized ${label}`);
    return bytes;
  } catch { throw new Error(`Missing, unsafe or oversized ${label}: ${relative}`); }
}

export function sourceDigest(files) {
  return sha(files.map((file) => `${file.sha256}  ${file.path}\n`).join(""));
}

export async function inspectEvidence({ contractPath, repoRoot = repository, referenceRoot }) {
  const root = await directory(repoRoot, "repository");
  string(contractPath, "contract path", 2000);
  const contractFile = path.isAbsolute(contractPath) ? path.relative(root, contractPath) : contractPath;
  const contract = JSON.parse(await regularFile(root, contractFile, 256 * 1024, "contract"));
  object(contract, ["schemaVersion", "contractID", "sourceFiles", "references", "screens"], "contract");
  requireValue(contract.schemaVersion === 1, "Unsupported evidence schema");
  uniqueID(contract.contractID, new Set(), "contract");
  list(contract.sourceFiles, 1, 80, "source files");
  const sources = new Set(); let sourceBytes = 0;
  for (const file of contract.sourceFiles) {
    object(file, ["path", "sha256"], "source"); relativeFile(file.path, "source"); digest(file.sha256, "source");
    requireValue(!sources.has(file.path), `Duplicate source path: ${file.path}`); sources.add(file.path);
    const bytes = await regularFile(root, file.path, 8 * 1024 * 1024, "source"); sourceBytes += bytes.length;
    requireValue(sourceBytes <= 32 * 1024 * 1024, "Source inventory exceeds 32 MiB");
    requireValue(sha(bytes) === file.sha256, `Stale source hash: ${file.path}`);
  }
  const sourceSHA256 = sourceDigest(contract.sourceFiles);
  const referencesRoot = referenceRoot === undefined ? undefined : await directory(referenceRoot, "reference root");
  list(contract.references, 1, 40, "references");
  const referenceIDs = new Set(), referenceChecks = [], pendingReferences = [];
  for (const reference of contract.references) {
    object(reference, ["id", "kind", "path", "file", "sha256", "url", "access"], "reference");
    uniqueID(reference.id, referenceIDs, "reference"); string(reference.access, "reference access");
    let status = "metadata-only";
    if (["approved-concept", "repository-contract"].includes(reference.kind)) {
      digest(reference.sha256, "reference");
      const local = reference.kind === "repository-contract";
      requireValue(reference.url === undefined && (local ? reference.file : reference.path) === undefined,
        `Ambiguous local reference: ${reference.id}`);
      const name = relativeFile(local ? reference.path : reference.file, "reference");
      requireValue(local || !name.includes("/"), "Approved concept file must be a basename");
      if (!local && referencesRoot === undefined) {
        status = "pending-reference-root"; pendingReferences.push(reference.id);
      } else {
        const bytes = await regularFile(local ? root : referencesRoot, name, 8 * 1024 * 1024, "reference");
        requireValue(sha(bytes) === reference.sha256, `Stale reference hash: ${reference.id}`); status = "hash-verified";
      }
    } else {
      requireValue(["official-guidance", "product-reference", "library-lead"].includes(reference.kind), "Unknown reference kind");
      requireValue(reference.path === undefined && reference.file === undefined && reference.sha256 === undefined,
        `URL reference cannot claim local verification: ${reference.id}`);
      string(reference.url, "reference URL", 2000);
      let url; try { url = new URL(reference.url); } catch { throw new Error("Invalid reference URL"); }
      requireValue(url.protocol === "https:" && !url.username && !url.password, "Reference URL must be public HTTPS metadata");
    }
    referenceChecks.push({ id: reference.id, kind: reference.kind, status, access: reference.access });
  }
  list(contract.screens, screenIDs.length, screenIDs.length, "screens");
  const screens = [], seenScreens = new Set(), evidenceIDs = new Set(); let imageBytes = 0;
  for (const screen of contract.screens) {
    object(screen, ["id", "root", "referenceIDs", "invariants", "openChecks", "evidence"], "screen");
    uniqueID(screen.id, seenScreens, "screen"); requireValue(screenIDs.includes(screen.id), "Unknown screen ID");
    relativeFile(screen.root, "screen root"); requireValue(sources.has(screen.root), `Screen root missing from source inventory: ${screen.id}`);
    list(screen.referenceIDs, 1, 40, "screen references");
    requireValue(new Set(screen.referenceIDs).size === screen.referenceIDs.length
      && screen.referenceIDs.every((id) => referenceIDs.has(id)), `Unknown or duplicate screen reference: ${screen.id}`);
    for (const [key, minimum] of [["invariants", 1], ["openChecks", 0]]) {
      list(screen[key], minimum, 40, key); screen[key].forEach((entry) => string(entry, key));
      requireValue(new Set(screen[key]).size === screen[key].length, `Duplicate ${key}`);
    }
    list(screen.evidence, 0, 12, "screen evidence"); const componentStudies = [], verifiedNativeScreens = [], historicalEvidence = [];
    for (const evidence of screen.evidence) {
      object(evidence, ["id", "path", "sha256", "width", "height", "appearance", "textSize", "scenario", "kind", "sourceBinding",
        "captureSourceSHA256", "captureIdentity"], "evidence");
      uniqueID(evidence.id, evidenceIDs, "evidence"); requireValue(evidenceIDs.size <= 48, "Too many evidence artifacts");
      relativeFile(evidence.path, "evidence"); digest(evidence.sha256, "evidence");
      requireValue(["component-study", "native-screen"].includes(evidence.kind), "Unknown evidence kind");
      requireValue(["historical-unbound", "verified-capture"].includes(evidence.sourceBinding), "Unknown source binding");
      requireValue(["light", "dark"].includes(evidence.appearance), "Invalid evidence appearance");
      string(evidence.textSize, "evidence text size", 80); string(evidence.scenario, "evidence scenario");
      const bytes = await regularFile(root, evidence.path, 2 * 1024 * 1024, "evidence"); imageBytes += bytes.length;
      requireValue(imageBytes <= 24 * 1024 * 1024, "Evidence exceeds 24 MiB");
      requireValue(sha(bytes) === evidence.sha256, `Stale artifact hash: ${evidence.id}`);
      const [width, height] = pngDimensions(bytes);
      requireValue(Number.isInteger(evidence.width) && evidence.width === width
        && (evidence.height === undefined || evidence.height === height), `Invalid evidence dimensions: ${evidence.id}`);
      if (evidence.sourceBinding === "historical-unbound") {
        requireValue(evidence.captureIdentity === undefined && evidence.captureSourceSHA256 === undefined,
          "Historical evidence cannot claim capture binding"); historicalEvidence.push(evidence.id);
      } else {
        digest(evidence.captureSourceSHA256, "capture source");
        requireValue(evidence.captureSourceSHA256 === sourceSHA256, `Capture/source mismatch: ${evidence.id}`);
        const identity = evidence.captureIdentity;
        object(identity, ["platform", "build", "os", "renderer", "hostBinarySHA256"], "capture identity");
        const platforms = evidence.kind === "component-study" ? ["macCatalyst", "iOS", "iPadOS"] : ["iOS", "iPadOS"];
        requireValue(platforms.includes(identity.platform), "Capture platform is incompatible with evidence kind");
        for (const key of ["build", "os", "renderer"]) string(identity[key], `capture ${key}`, 200);
        digest(identity.hostBinarySHA256, "capture host binary");
        if (evidence.kind === "native-screen") verifiedNativeScreens.push(evidence.id);
      }
      if (evidence.kind === "component-study") componentStudies.push(evidence.id);
    }
    screens.push({ id: screen.id, componentStudies, verifiedNativeScreens, historicalEvidence,
      openChecks: screen.openChecks, physicalChecksPending: screen.openChecks.length > 0 || verifiedNativeScreens.length === 0 });
  }
  const evidenceComplete = pendingReferences.length === 0 && screens.every((screen) => !screen.physicalChecksPending);
  return { schemaVersion: 1, contractID: contract.contractID, integrity: "passed", sourceSHA256,
    sourceFileCount: sources.size, referenceChecks, pendingReferences, screens, evidenceComplete,
    releaseAccepted: false, installAuthorized: false,
    captureProvenance: "Reviewer-supplied declaration, not independent compiler attestation; hashes establish freshness and integrity, not approval." };
}

export async function runCLI(argv, options = {}) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    requireValue(["--contract", "--reference-root", "--require-complete"].includes(key), `Unknown argument: ${key}`);
    requireValue(args[key] === undefined, `Duplicate argument: ${key}`);
    if (key === "--require-complete") args[key] = true;
    else { const value = argv[++index]; requireValue(value && !value.startsWith("--"), `Missing ${key}`); args[key] = value; }
  }
  requireValue(args["--contract"], "Required: --contract PATH [--reference-root DIR] [--require-complete]");
  const report = await inspectEvidence({ repoRoot: options.repoRoot, contractPath: args["--contract"], referenceRoot: args["--reference-root"] });
  (options.output ?? ((value) => process.stdout.write(value)))(JSON.stringify(report, null, 2) + "\n");
  return args["--require-complete"] && !report.evidenceComplete ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCLI(process.argv.slice(2)).then((code) => { process.exitCode = code; })
    .catch((error) => { process.stderr.write(`UI evidence check failed: ${error.message}\n`); process.exitCode = 1; });
}
