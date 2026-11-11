import test from "node:test";
import assert from "node:assert/strict";
import { deflateSync } from "node:zlib";
import { expectedIDs, expectedStates, pngDimensions, validateManifest } from "./review-visual-baselines.mjs";

function manifest() {
  const widths = [375, 375, 375, 1180, 650, 375, 320, 375, 375, 375];
  return { schema: 1, fixtureRevision: "fotty-components-20261010-v1", renderer: {
    platform: "macCatalyst", scale: "1", fixtureClock: "4000000000", fixtureTimeZone: "UTC",
    motion: "false", transparency: "false", animations: "disabled", os: "test-os", sdk: "test-sdk", xcode: "test-xcode", locale: "en_US",
  }, records: expectedIDs.map((id, index) => ({ id, file: `${id}.png`, sha256: "a".repeat(64),
    width: widths[index], height: 500, ...expectedStates[index] })) };
}

test("complete deterministic candidate manifest is accepted for inspection, not auto-approved", () => {
  assert.equal(validateManifest(manifest()).records.length, 10);
});
test("missing, duplicate and unknown fixture revisions fail closed", () => {
  const missing = manifest(); missing.records.pop(); assert.throws(() => validateManifest(missing));
  const duplicate = manifest(); duplicate.records[1] = duplicate.records[0]; assert.throws(() => validateManifest(duplicate));
  const changed = manifest(); changed.fixtureRevision = "new-unreviewed"; assert.throws(() => validateManifest(changed));
});
test("path traversal, mismatched name and missing hash are rejected", () => {
  for (const file of ["../secret.png", "/tmp/image.png", "different.png"]) {
    const value = manifest(); value.records[0].file = file; assert.throws(() => validateManifest(value));
  }
  const value = manifest(); value.records[0].sha256 = "invalid"; assert.throws(() => validateManifest(value));
});
test("changed renderer, non-pinned clocks and unknown SDK are rejected", () => {
  for (const [key, value] of [["platform", "iOS"], ["scale", "2"], ["fixtureClock", "now"], ["sdk", "unknown"],
    ["motion", "unknown"], ["transparency", "reduced"], ["animations", "enabled"]]) {
    const sample = manifest(); sample.renderer[key] = value; assert.throws(() => validateManifest(sample));
  }
  const observedReduced = manifest();
  observedReduced.renderer.motion = "true"; observedReduced.renderer.transparency = "true";
  assert.equal(validateManifest(observedReduced).renderer.motion, "true", "Both genuine system setting states can be fingerprinted");
});
test("oversized, zero and changed-width images cannot be approved", () => {
  for (const [key, value] of [["height", 4001], ["height", 0], ["width", 376]]) {
    const sample = manifest(); sample.records[0][key] = value; assert.throws(() => validateManifest(sample));
  }
});
test("an already approved manifest cannot be used as an unreviewed original", () => {
  for (const key of ["reviewedBy", "reviewedAt", "sourceReceipt"]) {
    const sample = manifest(); sample[key] = "test"; assert.throws(() => validateManifest(sample));
  }
});
test("valid but mislabeled appearance, surface and text-size states fail closed", () => {
  for (const [key, value] of [["surface", "sources"], ["appearance", "light"], ["textSize", "accessibility2"]]) {
    const sample = manifest(); sample.records[0][key] = value; assert.throws(() => validateManifest(sample));
  }
});
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
// Independently calculate fixture CRCs without reusing the production parser.
function pngChunk(type, data = Buffer.alloc(0)) {
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  let crc = 0xffffffff;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([length, body, checksum]);
}
function pngParts(width = 375, height = 500) {
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6; // RGBA8, ordinary compression/filter, no interlace.
  const pixels = Buffer.alloc(height * (1 + width * 4)); // Filter byte + transparent RGBA per scanline.
  return { header: pngChunk("IHDR", header), payload: deflateSync(pixels) };
}
test("PNG inspection requires a complete CRC-checked image-data stream", () => {
  const { header, payload } = pngParts();
  const bytes = Buffer.concat([pngSignature, header, pngChunk("IDAT", payload), pngChunk("IEND")]);
  assert.deepEqual(pngDimensions(bytes), [375, 500]);
  const split = Buffer.concat([pngSignature, header, pngChunk("IDAT", payload.subarray(0, 1)),
    pngChunk("IDAT", payload.subarray(1)), pngChunk("IEND")]);
  assert.deepEqual(pngDimensions(split), [375, 500], "A legal zlib header may cross contiguous IDAT chunks");
  const withAncillary = Buffer.concat([pngSignature, header, pngChunk("tEXt", Buffer.from("note\0test")),
    pngChunk("IDAT", payload), pngChunk("IEND")]);
  assert.deepEqual(pngDimensions(withAncillary), [375, 500]);
  assert.throws(() => pngDimensions(Buffer.alloc(32)));
  bytes[0] = 0; assert.throws(() => pngDimensions(bytes));
});
test("header-only, corrupted, missing-data and malformed PNG chunks cannot be approved", () => {
  const { header, payload } = pngParts(4, 4);
  const valid = Buffer.concat([pngSignature, header, pngChunk("IDAT", payload), pngChunk("IEND")]);
  const badCRC = Buffer.from(valid); badCRC[29] ^= 1;
  const badPayloadCRC = Buffer.from(valid); badPayloadCRC[45] ^= 1;
  const headerOnly = Buffer.alloc(33); pngSignature.copy(headerOnly);
  headerOnly.writeUInt32BE(13, 8); headerOnly.write("IHDR", 12);
  headerOnly.writeUInt32BE(375, 16); headerOnly.writeUInt32BE(500, 20);
  const badHeader = Buffer.alloc(13); badHeader.writeUInt32BE(4); badHeader.writeUInt32BE(4, 4);
  badHeader[8] = 7; badHeader[9] = 6;
  const badLength = Buffer.from(valid); badLength.writeUInt32BE(0xffffffff, 33);
  const samples = [headerOnly, badCRC, badPayloadCRC, badLength, valid.subarray(0, valid.length - 1),
    Buffer.concat([valid, Buffer.from([0])]),
    Buffer.concat([pngSignature, header, pngChunk("IEND")]),
    Buffer.concat([pngSignature, header, pngChunk("IDAT"), pngChunk("IEND")]),
    Buffer.concat([pngSignature, header, pngChunk("IDAT", payload)]),
    Buffer.concat([pngSignature, header, header, pngChunk("IDAT", payload), pngChunk("IEND")]),
    Buffer.concat([pngSignature, pngChunk("IHDR", badHeader), pngChunk("IDAT", payload), pngChunk("IEND")]),
    Buffer.concat([pngSignature, header, pngChunk("IDAT", payload.subarray(0, 1)),
      pngChunk("tEXt", Buffer.from("note\0test")), pngChunk("IDAT", payload.subarray(1)), pngChunk("IEND")]),
    Buffer.concat([pngSignature, header, pngChunk("ABCD"), pngChunk("IDAT", payload), pngChunk("IEND")]),
    Buffer.concat([pngSignature, header, pngChunk("\u00c9HDR"), pngChunk("IDAT", payload), pngChunk("IEND")]),
    Buffer.concat([pngSignature, header, pngChunk("IDAT", Buffer.alloc(8)), pngChunk("IEND")]),
    Buffer.alloc(2 * 1024 * 1024 + 1)];
  for (const sample of samples) assert.throws(() => pngDimensions(sample));
});
