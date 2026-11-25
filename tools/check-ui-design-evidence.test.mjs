import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, writeFile, readFile, realpath, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { deflateSync } from "node:zlib";
import { inspectEvidence, runCLI, screenIDs, sourceDigest } from "./check-ui-design-evidence.mjs";

const hash = (value) => createHash("sha256").update(value).digest("hex");
function chunk(type, data = Buffer.alloc(0)) {
  const body = Buffer.concat([Buffer.from(type), data]); let crc = 0xffffffff;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  const size = Buffer.alloc(4); size.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([size, body, checksum]);
}
function png(width = 2, height = 3) {
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.alloc(height * (1 + width * 4)))), chunk("IEND")]);
}

async function fixture(t) {
  const folder = await realpath(await mkdtemp(path.join(tmpdir(), "FottyDesignEvidenceTest-")));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const root = path.join(folder, "repo"), references = path.join(folder, "references");
  await mkdir(path.join(root, "src"), { recursive: true }); await mkdir(path.join(root, "images"));
  await mkdir(references);
  const sourceFiles = [];
  for (const id of screenIDs) {
    const file = `src/${id}.swift`, content = `// ${id}\n`;
    await writeFile(path.join(root, file), content); sourceFiles.push({ path: file, sha256: hash(content) });
  }
  await writeFile(path.join(root, "screen-contract.md"), "Approved hierarchy\n");
  await writeFile(path.join(references, "concept.html"), "<h1>Approved concept</h1>");
  const bytes = png(); await writeFile(path.join(root, "images/study.png"), bytes);
  const contract = {
    schemaVersion: 1, contractID: "test-ui-v1", sourceFiles,
    references: [
      { id: "concept", kind: "approved-concept", file: "concept.html", sha256: hash("<h1>Approved concept</h1>"), access: "Owner approved; local" },
      { id: "hierarchy", kind: "repository-contract", path: "screen-contract.md", sha256: hash("Approved hierarchy\n"), access: "Read 2026-10-25" },
      ...["official-guidance", "product-reference", "library-lead"].map((kind) => ({ id: kind, kind,
        url: `https://example.invalid/${kind}`, access: "Metadata only; not fetched" })),
    ],
    screens: screenIDs.map((id) => ({ id, root: `src/${id}.swift`, referenceIDs: ["concept", "hierarchy"],
      invariants: ["Primary action remains visible"], openChecks: ["Physical comparison pending"], evidence: [] })),
  };
  contract.screens[0].evidence.push({ id: "home-study", path: "images/study.png", sha256: hash(bytes), width: 2,
    height: 3, appearance: "dark", textSize: "large", scenario: "Illustrative long teams", kind: "component-study", sourceBinding: "historical-unbound" });
  const save = () => writeFile(path.join(root, "contract.json"), JSON.stringify(contract));
  const inspect = async (options = {}) => {
    await save(); return inspectEvidence({ repoRoot: root, contractPath: "contract.json", referenceRoot: references, ...options });
  };
  return { root, references, contract, save, inspect, bytes };
}

function addNativeEvidence(contract) {
  const artifact = contract.screens[0].evidence[0];
  for (const screen of contract.screens) {
    screen.openChecks = [];
    screen.evidence = [{ ...artifact, id: `${screen.id}-native`, kind: "native-screen", sourceBinding: "verified-capture",
      captureSourceSHA256: sourceDigest(contract.sourceFiles),
      captureIdentity: { platform: "iOS", build: "176", os: "27.0.1", renderer: "physical-device-screenshot",
        hostBinarySHA256: "b".repeat(64) } }];
  }
}

test("historical studies retain integrity but never grant native/release acceptance", async (t) => {
  const f = await fixture(t), before = await readFile(path.join(f.root, "images/study.png"));
  const report = await f.inspect();
  assert.equal(report.integrity, "passed"); assert.equal(report.evidenceComplete, false);
  assert.equal(report.releaseAccepted, false); assert.equal(report.installAuthorized, false);
  assert.deepEqual(report.screens[0].componentStudies, ["home-study"]);
  assert.deepEqual(report.screens[0].verifiedNativeScreens, []);
  assert.ok(report.screens.every((screen) => screen.physicalChecksPending));
  assert.match(report.captureProvenance, /not independent compiler attestation/);
  assert.deepEqual(await readFile(path.join(f.root, "images/study.png")), before);
  assert.equal(report.sourceSHA256, hash(f.contract.sourceFiles.map((entry) => `${entry.sha256}  ${entry.path}\n`).join("")));
  assert.equal(report.referenceChecks.find((item) => item.id === "product-reference").status, "metadata-only");
});

test("missing reference root is explicitly pending, not a verified hash", async (t) => {
  const f = await fixture(t); addNativeEvidence(f.contract);
  const report = await f.inspect({ referenceRoot: undefined });
  assert.deepEqual(report.pendingReferences, ["concept"]); assert.equal(report.evidenceComplete, false);
  assert.equal(report.referenceChecks[0].status, "pending-reference-root");
});

test("changed source, PNG, concept and repository reference hashes fail", async (t) => {
  for (const target of ["source", "artifact", "concept", "repository reference"]) {
    await t.test(target, async (sub) => {
      const f = await fixture(sub);
      const name = { source: path.join(f.root, "src/home.swift"), artifact: path.join(f.root, "images/study.png"),
        concept: path.join(f.references, "concept.html"), "repository reference": path.join(f.root, "screen-contract.md") }[target];
      await writeFile(name, "changed"); await assert.rejects(f.inspect(), /Stale (source|artifact|reference) hash/);
    });
  }
});

test("six known screens and unique source/reference/evidence IDs are required", async (t) => {
  for (const mutate of [
    (c) => c.screens.pop(), (c) => { c.screens[5].id = "home"; }, (c) => { c.screens[5].id = "unknown-screen"; },
    (c) => c.references.push(c.references[0]), (c) => c.sourceFiles.push(c.sourceFiles[0]),
    (c) => c.screens[1].evidence.push(c.screens[0].evidence[0]),
    (c) => c.screens[0].referenceIDs.push("missing"), (c) => c.screens[0].referenceIDs.push("concept"),
    (c) => { c.screens[0].root = "not-in-inventory.swift"; },
  ]) {
    await t.test(String(mutate), async (sub) => { const f = await fixture(sub); mutate(f.contract); await assert.rejects(f.inspect()); });
  }
});

test("declared dimensions and bounded PNG structure must agree", async (t) => {
  for (const mutate of [
    (f) => { f.contract.screens[0].evidence[0].width = 3; },
    (f) => { f.contract.screens[0].evidence[0].height = 4; },
    (f) => { f.contract.screens[0].evidence[0].width = "2"; },
    async (f) => {
      const bytes = png(0, 3); await writeFile(path.join(f.root, "images/study.png"), bytes);
      f.contract.screens[0].evidence[0].sha256 = hash(bytes);
    },
  ]) {
    await t.test(String(mutate), async (sub) => { const f = await fixture(sub); await mutate(f); await assert.rejects(f.inspect(), /dimensions/i); });
  }
});

test("historical native-screen labels do not qualify and cannot claim binding", async (t) => {
  const f = await fixture(t); f.contract.screens[0].openChecks = [];
  f.contract.screens[0].evidence[0].kind = "native-screen";
  const report = await f.inspect();
  assert.deepEqual(report.screens[0].verifiedNativeScreens, []); assert.equal(report.screens[0].physicalChecksPending, true);
  f.contract.screens[0].evidence[0].captureSourceSHA256 = sourceDigest(f.contract.sourceFiles);
  await assert.rejects(f.inspect(), /Historical evidence cannot claim/);
});

test("declared native captures require current source and complete mobile capture identity", async (t) => {
  for (const mutate of [
    (e) => { delete e.captureIdentity; }, (e) => { e.captureSourceSHA256 = "f".repeat(64); },
    (e) => { e.captureIdentity.platform = "macCatalyst"; }, (e) => { e.captureIdentity.build = ""; },
    (e) => { delete e.captureIdentity.os; }, (e) => { e.captureIdentity.renderer = ""; },
    (e) => { e.captureIdentity.hostBinarySHA256 = "bad"; },
  ]) {
    await t.test(String(mutate), async (sub) => {
      const f = await fixture(sub); addNativeEvidence(f.contract); mutate(f.contract.screens[0].evidence[0]);
      await assert.rejects(f.inspect());
    });
  }
});

test("valid declarations never close open checks or grant release authority", async (t) => {
  const f = await fixture(t); addNativeEvidence(f.contract);
  f.contract.screens[0].openChecks = ["VoiceOver still pending"];
  let report = await f.inspect(); assert.equal(report.evidenceComplete, false);
  assert.deepEqual(report.screens[0].openChecks, ["VoiceOver still pending"]);
  f.contract.screens[0].openChecks = [];
  report = await f.inspect(); assert.equal(report.evidenceComplete, true);
  assert.equal(report.releaseAccepted, false); assert.equal(report.installAuthorized, false);
  f.contract.sourceFiles.reverse(); await assert.rejects(f.inspect(), /Capture\/source mismatch/);
});

test("source-bound Catalyst studies cannot qualify as native screens or complete evidence", async (t) => {
  const f = await fixture(t); addNativeEvidence(f.contract);
  const study = f.contract.screens[0].evidence[0];
  study.kind = "component-study"; study.captureIdentity.platform = "macCatalyst";
  const report = await f.inspect();
  assert.deepEqual(report.screens[0].componentStudies, [study.id]);
  assert.deepEqual(report.screens[0].historicalEvidence, []);
  assert.deepEqual(report.screens[0].verifiedNativeScreens, []);
  assert.equal(report.screens[0].physicalChecksPending, true);
  assert.equal(report.evidenceComplete, false);
  assert.equal(report.releaseAccepted, false);
  study.kind = "native-screen";
  await assert.rejects(f.inspect(), /Capture platform is incompatible/);
});

test("unknown JSON fields, unsafe paths and misleading URL metadata fail closed", async (t) => {
  for (const mutate of [
    (c) => { c.schemaVersion = 2; }, (c) => { c.releaseAccepted = true; },
    (c) => { c.screens[0].evidence[0].sourceBinding = "approved"; },
    (c) => { c.sourceFiles[0].path = "../outside.swift"; },
    (c) => { c.screens[0].evidence[0].path = "/absolute.png"; },
    (c) => { c.references[0].file = "nested/concept.html"; },
    (c) => { c.references[1].path = "src/../screen-contract.md"; },
    (c) => { c.references[2].url = "https://user:password@example.invalid"; },
    (c) => { c.references[2].url = "http://example.invalid"; },
    (c) => { c.references[2].sha256 = "a".repeat(64); },
  ]) {
    await t.test(String(mutate), async (sub) => { const f = await fixture(sub); mutate(f.contract); await assert.rejects(f.inspect()); });
  }
});

test("file and ancestor-directory symlinks cannot escape evidence roots", async (t) => {
  for (const target of ["source-directory", "artifact", "reference-file", "reference-root", "contract"]) {
    await t.test(target, async (sub) => {
      const f = await fixture(sub); let options = {};
      if (target === "source-directory") {
        await symlink(path.join(f.root, "src"), path.join(f.root, "linked"));
        f.contract.sourceFiles[0].path = "linked/home.swift";
      } else if (target === "artifact") {
        await symlink(path.join(f.root, "images/study.png"), path.join(f.root, "linked.png"));
        f.contract.screens[0].evidence[0].path = "linked.png";
      } else if (target === "reference-file") {
        await symlink(path.join(f.references, "concept.html"), path.join(f.references, "linked.html"));
        f.contract.references[0].file = "linked.html";
      } else if (target === "reference-root") {
        const linked = path.join(f.root, "linked-references"); await symlink(f.references, linked); options.referenceRoot = linked;
      } else {
        await f.save(); await symlink(path.join(f.root, "contract.json"), path.join(f.root, "linked.json")); options.contractPath = "linked.json";
      }
      await assert.rejects(f.inspect(options), /unsafe|symlinked/i);
    });
  }
});

test("CLI inspection succeeds on coherent incomplete pack, strict mode fails, args fail closed", async (t) => {
  const f = await fixture(t); await f.save(); const output = [];
  const options = { repoRoot: f.root, output: (text) => output.push(JSON.parse(text)) };
  const args = ["--contract", "contract.json", "--reference-root", f.references];
  assert.equal(await runCLI(args, options), 0); assert.equal(output.at(-1).evidenceComplete, false);
  assert.equal(await runCLI([...args, "--require-complete"], options), 1);
  addNativeEvidence(f.contract); await f.save();
  assert.equal(await runCLI([...args, "--require-complete"], options), 0);
  assert.equal(output.at(-1).releaseAccepted, false);
  assert.equal(await runCLI(["--contract", "contract.json", "--require-complete"], options), 1);
  for (const invalid of [[], ["--contract"], ["--wat"], [...args, "--contract", "contract.json"],
    [...args, "--reference-root", f.references], [...args, "--require-complete", "--require-complete"],
    [...args, "--require-complete", "true"], ["--contract", "../outside.json"]]) {
    await assert.rejects(runCLI(invalid, options));
  }
});
