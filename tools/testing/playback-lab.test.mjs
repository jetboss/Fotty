import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { playbackLab, physicalGates, selectionFor, checkLab } from "./playback-lab.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const clone = () => structuredClone(playbackLab);

test("every controlled scenario points to a real XCTest without claiming execution or physical proof", async () => {
  const result = await checkLab(root);
  assert.equal(result.scenarios, 8);
  assert.ok(result.selectedTests >= 20);
  assert.equal(result.xctestExecutionVerified, false);
  assert.equal(result.decodedPlaybackVerified, false);
  assert.equal(physicalGates.length, 5);
});

test("missing test implementations cannot silently turn the lab green", async () => {
  const scenarios = clone();
  scenarios[0].tests[0] = "LocalStreamProxyTests/testMissingPlaybackLabScenario";
  await assert.rejects(checkLab(root, scenarios), /Missing XCTest implementation/);
});

test("duplicate scenario IDs, traversal selectors and inflated evidence claims fail closed", () => {
  for (const mutate of [
    (rows) => { rows[1].id = rows[0].id; },
    (rows) => { rows[0].tests[0] = "../../OtherTests/testNotAllowed"; },
    (rows) => { rows[0].evidence = "decoded-playback"; },
    (rows) => { rows[0].tests = []; }
  ]) {
    const scenarios = clone(); mutate(scenarios);
    assert.throws(() => selectionFor(scenarios));
  }
});

test("repeated test coverage yields one XCTest argument without changing scenario identity", () => {
  const scenarios = clone(), before = selectionFor(scenarios);
  scenarios[1].tests.push(scenarios[0].tests[0]);
  assert.deepEqual(selectionFor(scenarios), before);
});
