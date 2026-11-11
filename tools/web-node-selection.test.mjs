import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, chmodSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const helper = join(dirname(fileURLToPath(import.meta.url)), "lib/web-node.sh");
const shellQuote = (value) => `'${value.replaceAll("'", "'\\''")}'`;

function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), "FottyNodeSelection-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return function node(name, version, platform = "darwin", executablePath) {
    const script = join(directory, `${name}.cjs`), executable = join(directory, name);
    writeFileSync(script, `
      const vm = require("node:vm");
      Object.defineProperty(process.versions, "node", { value: ${JSON.stringify(version)} });
      Object.defineProperty(process, "platform", { value: ${JSON.stringify(platform)} });
      ${executablePath ? `Object.defineProperty(process, "execPath", { value: ${JSON.stringify(executablePath)} });` : ""}
      const code = process.argv[3];
      process.argv = [process.execPath, ...process.argv.slice(4)];
      vm.runInThisContext(code);
    `);
    writeFileSync(executable, `#!/bin/sh\nexec ${shellQuote(process.execPath)} ${shellQuote(script)} "$@"\n`);
    chmodSync(executable, 0o700);
    return executable;
  };
}

function select(major, candidates) {
  return spawnSync("/bin/bash", ["-c", 'source "$1"; shift; fotty_select_web_node "$@"',
    "fotty-node-test", helper, major, ...candidates], { encoding: "utf8" });
}

test("the declared Node major is selected even when an unsupported newer runtime comes first", (t) => {
  const node = fixture(t);
  const supported = node("supported node", "24.22.2");
  const result = select("24", [node("eol", "25.5.0"), node("other-lts", "26.12.0"), supported]);
  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), supported);
});

test("unsupported and alpha majors do not silently satisfy the build requirement", (t) => {
  const node = fixture(t);
  for (const version of ["22.22.0", "25.5.0", "26.12.0", "27.0.0"]) {
    const result = select("24", [node(`v${version}`, version)]);
    assert.equal(result.status, 1, version);
    assert.equal(result.stdout, "");
  }
});

test("a Linux runtime or aliased Codex bundled runtime is rejected", (t) => {
  const node = fixture(t);
  const result = select("24", [node("linux", "24.22.2", "linux"),
    node("bundled-alias", "24.22.2", "darwin", "/Applications/Codex.app/Contents/Resources/node")]);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
});

test("missing candidates and malformed major declarations fail without invoking a build", (t) => {
  const node = fixture(t);
  assert.equal(select("24", ["/nonexistent/FottyNode", node("old", "25.5.0")]).status, 1);
  assert.equal(select("24+", [node("supported", "24.22.2")]).status, 1);
});
