#!/usr/bin/env node
// Explicit reviewed artifact promotion, not a recorder or automatic blessing.
// No network, image transformation, Xcode invocation or production data.
import { createHash } from "node:crypto";
import { lstat, readFile, readdir, mkdir, writeFile, copyFile, realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const expectedIDs = Object.freeze([
  "home-phone-dark", "home-phone-light", "home-phone-large-text",
  "home-ipad-landscape", "home-ipad-narrow", "sources-phone-dark",
  "sources-phone-large-text", "controls-dark", "controls-light", "badges-loaded-and-missing",
]);
const fixtureRevision = "fotty-components-20261010-v1";
const widths = [375, 375, 375, 1180, 650, 375, 320, 375, 375, 375];
export const expectedStates = Object.freeze(expectedIDs.map((id, index) => Object.freeze({
  surface: id.startsWith("home") ? "home" : id.startsWith("sources") ? "sources" : id.startsWith("controls") ? "controls" : "badges",
  appearance: [1, 4, 6, 8, 9].includes(index) ? "light" : "dark",
  textSize: index === 2 ? "accessibility2" : index === 6 ? "accessibility3" : "large",
})));
const hash = (data) => createHash("sha256").update(data).digest("hex");
const requireValue = (value, message) => { if (!value) throw new Error(message); };

export function validateManifest(manifest) {
  requireValue(manifest?.schema === 1 && manifest.fixtureRevision === fixtureRevision, "Unknown fixture/schema revision");
  requireValue(manifest.reviewedBy === undefined && manifest.reviewedAt === undefined
    && manifest.sourceReceipt === undefined, "Candidates must be unapproved originals");
  requireValue(manifest.renderer?.platform === "macCatalyst" && manifest.renderer.scale === "1"
    && manifest.renderer.fixtureClock === "4000000000" && manifest.renderer.fixtureTimeZone === "UTC"
    && ["true", "false"].includes(manifest.renderer.motion)
    && ["true", "false"].includes(manifest.renderer.transparency)
    && manifest.renderer.animations === "disabled",
  "Missing pinned deterministic renderer settings");
  requireValue(["os", "sdk", "xcode", "locale"].every((key) => typeof manifest.renderer[key] === "string"
    && manifest.renderer[key].length > 0 && manifest.renderer[key] !== "unknown"), "Missing renderer/toolchain identity");
  requireValue(Array.isArray(manifest.records) && manifest.records.length === expectedIDs.length, "Incomplete render set");
  requireValue(new Set(manifest.records.map((row) => row?.id)).size === expectedIDs.length, "Duplicate fixture IDs");
  for (let index = 0; index < expectedIDs.length; index += 1) {
    const id = expectedIDs[index], row = manifest.records.find((record) => record?.id === id);
    requireValue(row && row.file === `${id}.png` && /^[a-f0-9]{64}$/.test(row.sha256), `Invalid artifact: ${id}`);
    requireValue(row.width === widths[index] && Number.isInteger(row.height) && row.height > 0
      && row.height <= 4000 && row.width * row.height <= 4_000_000, `Invalid dimensions: ${id}`);
    requireValue(Object.entries(expectedStates[index]).every(([key, value]) => row[key] === value),
      `Incorrect render state: ${id}`);
  }
  return manifest;
}

export function pngDimensions(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  requireValue(Buffer.isBuffer(bytes) && bytes.length >= 57 && bytes.length <= 2 * 1024 * 1024
    && bytes.subarray(0, 8).equals(signature), "Invalid or oversized PNG");
  // Validate the bounded chunk stream before approval. This is structural
  // validation, not raster decoding: UIKit comparison and explicit visual
  // inspection still establish whether the compressed image actually renders.
  const crcTable = Array.from({ length: 256 }, (_, value) => {
    let crc = value;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    return crc >>> 0;
  });
  const crc32 = (start, end) => {
    let crc = 0xffffffff;
    for (let index = start; index < end; index += 1) crc = crcTable[(crc ^ bytes[index]) & 255] ^ (crc >>> 8);
    return (crc ^ 0xffffffff) >>> 0;
  };
  let offset = 8, width = 0, height = 0, colorType = -1, bitDepth = 0;
  let paletteSeen = false, idatSeen = false, idatEnded = false, endSeen = false, idatBytes = 0;
  const zlibPrefix = [];
  while (offset < bytes.length) {
    requireValue(offset + 12 <= bytes.length, "Truncated PNG chunk");
    const length = bytes.readUInt32BE(offset);
    const end = offset + 12 + length;
    requireValue(length <= 2 * 1024 * 1024 && end <= bytes.length, "Truncated or oversized PNG chunk");
    const type = bytes.subarray(offset + 4, offset + 8).toString("latin1");
    requireValue(/^[A-Za-z]{4}$/.test(type) && /[A-Z]/.test(type[2]), "Invalid PNG chunk type");
    requireValue(crc32(offset + 4, end - 4) === bytes.readUInt32BE(end - 4), `Invalid PNG CRC: ${type}`);
    if (offset === 8) requireValue(type === "IHDR", "PNG must begin with IHDR");
    if (type === "IHDR") {
      requireValue(offset === 8 && length === 13, "Duplicate or malformed PNG IHDR");
      width = bytes.readUInt32BE(offset + 8); height = bytes.readUInt32BE(offset + 12);
      bitDepth = bytes[offset + 16]; colorType = bytes[offset + 17];
      const depths = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
      requireValue(width > 0 && width <= 2000 && height > 0 && height <= 4000
        && width * height <= 4_000_000, "Invalid PNG dimensions");
      requireValue(depths[colorType]?.includes(bitDepth) && bytes[offset + 18] === 0
        && bytes[offset + 19] === 0 && [0, 1].includes(bytes[offset + 20]), "Invalid PNG image format");
    } else if (type === "PLTE") {
      requireValue(!paletteSeen && !idatSeen && ![0, 4].includes(colorType)
        && length > 0 && length <= 768 && length % 3 === 0
        && (colorType !== 3 || length / 3 <= 2 ** bitDepth), "Invalid PNG palette");
      paletteSeen = true;
    } else if (type === "IDAT") {
      requireValue(!idatEnded && (colorType !== 3 || paletteSeen), "Invalid PNG image-data order");
      idatSeen = true; idatBytes += length;
      for (let index = offset + 8; index < end - 4 && zlibPrefix.length < 2; index += 1) zlibPrefix.push(bytes[index]);
    } else if (type === "IEND") {
      requireValue(length === 0 && idatSeen && idatBytes >= 6 && end === bytes.length,
        "Missing image data or malformed PNG end");
      endSeen = true;
    } else {
      requireValue(/[a-z]/.test(type[0]), `Unsupported critical PNG chunk: ${type}`);
    }
    if (idatSeen && type !== "IDAT") idatEnded = true;
    offset = end;
  }
  requireValue(endSeen && zlibPrefix.length === 2 && (zlibPrefix[0] & 15) === 8
    && (zlibPrefix[0] >>> 4) <= 7 && (zlibPrefix[1] & 32) === 0
    && ((zlibPrefix[0] << 8) | zlibPrefix[1]) % 31 === 0, "Incomplete PNG or invalid compressed-image header");
  return [width, height];
}

async function regularFile(file, maximumBytes) {
  const attributes = await lstat(file);
  requireValue(attributes.isFile() && !attributes.isSymbolicLink() && attributes.size > 0
    && attributes.size <= maximumBytes, `Unsafe or oversized file: ${path.basename(file)}`);
  return readFile(file);
}

export async function inspectCandidates(directory) {
  requireValue(path.isAbsolute(directory) && directory.startsWith("/private/tmp/FottyVisual."),
    "Candidates must use a fresh owned /private/tmp/FottyVisual.XXXXXX directory");
  const attributes = await lstat(directory);
  requireValue(attributes.isDirectory() && !attributes.isSymbolicLink() && await realpath(directory) === directory,
    "Symlinked/non-directory candidates are rejected");
  const manifest = validateManifest(JSON.parse(await regularFile(path.join(directory, "candidates.json"), 32_768)));
  const files = await readdir(directory);
  const expectedFiles = ["candidates.json", ...expectedIDs.map((id) => `${id}.png`)];
  requireValue(files.length === expectedFiles.length && files.every((name) => expectedFiles.includes(name)),
    "Unexpected files in candidates directory");
  let total = 0;
  for (const row of manifest.records) {
    const bytes = await regularFile(path.join(directory, row.file), 2 * 1024 * 1024);
    total += bytes.length;
    requireValue(hash(bytes) === row.sha256, `Candidate changed since rendering: ${row.id}`);
    const [width, height] = pngDimensions(bytes);
    requireValue(width === row.width && height === row.height, `PNG dimensions disagree: ${row.id}`);
  }
  requireValue(total <= 8 * 1024 * 1024, "Baseline set exceeds the 8 MiB resource budget");
  return { manifest, total };
}

async function main(argv) {
  if (argv.length === 1 && argv[0] === "--help") {
    process.stdout.write("Inspect: node tools/review-visual-baselines.mjs --candidates /private/tmp/FottyVisual.XXXXXX --inspect\n"
      + "Approve after inspecting every PNG: --candidates DIR --reviewer NAME --reviewed ID1,ID2,... --source-receipt 64_HEX_SHA\n"
      + "Existing baselines are never overwritten by this command. A rebaseline requires separate deliberate review.\n");
    return;
  }
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    requireValue(["--candidates", "--reviewer", "--reviewed", "--source-receipt", "--inspect"].includes(key), `Unknown argument: ${key}`);
    requireValue(args[key] === undefined, `Duplicate argument: ${key}`);
    if (key === "--inspect") args[key] = true;
    else { const value = argv[++index]; requireValue(value && !value.startsWith("--"), `Missing ${key}`); args[key] = value; }
  }
  const { manifest, total } = await inspectCandidates(args["--candidates"] ?? "");
  if (args["--inspect"]) {
    requireValue(Object.keys(args).length === 2, "Inspection cannot include approval arguments");
    process.stdout.write(JSON.stringify({ candidateCount: manifest.records.length, totalBytes: total,
      renderer: manifest.renderer, records: manifest.records }, null, 2) + "\n");
    return;
  }
  const reviewer = args["--reviewer"]?.trim();
  requireValue(reviewer && reviewer.length <= 120 && !/[\r\n]/.test(reviewer), "Explicit reviewer is required");
  const reviewed = args["--reviewed"]?.split(",");
  requireValue(reviewed?.length === expectedIDs.length && new Set(reviewed).size === expectedIDs.length
    && expectedIDs.every((id) => reviewed.includes(id)), "Explicit review acknowledgement must name each of the 10 images");
  const receipt = args["--source-receipt"];
  requireValue(/^[a-f0-9]{64}$/.test(receipt ?? ""), "Verified source receipt SHA-256 is required");
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const destination = path.join(root, "FottyTests", "Fixtures", "VisualBaselines");
  const fixtures = path.dirname(destination);
  try { await mkdir(fixtures, { recursive: false }); }
  catch (error) { if (error.code !== "EEXIST") throw error; }
  const fixtureAttributes = await lstat(fixtures);
  requireValue(fixtureAttributes.isDirectory() && !fixtureAttributes.isSymbolicLink()
    && await realpath(fixtures) === fixtures, "Unsafe fixtures destination");
  // Exclusive creation prevents a record/review command from quietly replacing
  // the last accepted design. Neither failed renders nor missing baselines bless.
  await mkdir(destination, { recursive: false });
  for (const row of manifest.records) {
    await copyFile(path.join(args["--candidates"], row.file), path.join(destination, row.file), 1);
  }
  const reviewedManifest = { ...manifest, reviewedBy: reviewer, reviewedAt: new Date().toISOString(), sourceReceipt: receipt };
  // Manifest last: an interrupted copy remains unapproved and fails the gate.
  await writeFile(path.join(destination, "manifest.json"), JSON.stringify(reviewedManifest, null, 2) + "\n", { flag: "wx" });
  process.stdout.write(`Approved ${manifest.records.length} explicitly reviewed component baselines (${total} bytes). Re-run the non-recording gate.\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
