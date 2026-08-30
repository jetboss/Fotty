// Offline diagnostic probes against unchanged production code.
// Exit 1 means one or more stated safety expectations are violated, not a build failure.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { extractMonitor, root } from './measure-js.mjs';

const results = [];
const productionMonitor = extractMonitor();
const swiftTests = fs.readFileSync(path.join(root, 'FottyTests/PlaybackPolicyTests.swift'), 'utf8');
const fixtureStart = swiftTests.indexOf('context.evaluateScript(#"""', swiftTests.indexOf('private func makeWebMonitorContext()'));
const fixtureEnd = swiftTests.indexOf('"""#)', fixtureStart);
assert(fixtureStart >= 0 && fixtureEnd > fixtureStart);
const fixtureCode = swiftTests.slice(fixtureStart + 'context.evaluateScript(#"""'.length, fixtureEnd);
function monitorContext() {
  const context = vm.createContext({});
  vm.runInContext(fixtureCode, context, { timeout: 1000 });
  vm.runInContext(productionMonitor.code, context, { timeout: 1000 });
  assert.equal(vm.runInContext("timers.some(t => t.delay === 20000)", context), true);
  return context;
}

{
  const context = monitorContext();
  vm.runInContext("emit('playing', video); video.pause(); messages=[]; clock+=60000; intervals.forEach(t=>t.fn())", context);
  const observed = vm.runInContext("messages.filter(m=>m.type==='stream_failed').length", context);
  assert.equal(observed, 0, 'Existing deliberate-pause control must pass');
  results.push({ id: 'control-paused-video', expectedFailures: 0, observedFailures: observed, pass: observed === 0 });
}

{
  const context = monitorContext();
  vm.runInContext(`
    video.currentTime=300; emit('playing', video); messages=[];
    video.isConnected=false;
    video=Object.assign({},video,{isConnected:true,currentTime:1,paused:false});
    for(let n=0;n<40;n++) { clock+=1000; video.currentTime+=1; emit('timeupdate',video); intervals.forEach(t=>t.fn()); }
  `, context);
  const observed = vm.runInContext("messages.filter(m=>m.type==='stream_failed').map(m=>m.reason)", context);
  results.push({ id: 'replacement-video-progress', expected: 'No stall while replacement video advances every second',
    observed: Array.from(observed), pass: observed.length === 0 });
}

{
  const context = monitorContext();
  vm.runInContext("emit('playing',video); messages=[]; emit('error',{tagName:'VIDEO',error:{code:4}})", context);
  const observed = vm.runInContext("messages.filter(m=>m.type==='stream_failed').map(m=>m.reason)", context);
  results.push({ id: 'unrelated-video-error', expected: 'An unrelated video cannot fail the confirmed broadcast',
    observed: Array.from(observed), pass: observed.length === 0 });
}

const { resolveFplScoring } = await import(pathToFileURL(path.join(root, 'web/workers/playback/src/fpl-scoring.mjs')));
const scoringTests = fs.readFileSync(path.join(root, 'web/workers/playback/src/fpl-scoring.test.mjs'), 'utf8');
const scoringStart = scoringTests.indexOf('function player(');
const scoringEnd = scoringTests.indexOf('test("projects');
assert(scoringStart >= 0 && scoringEnd > scoringStart);
const scoringContext = vm.createContext({});
vm.runInContext(scoringTests.slice(scoringStart, scoringEnd), scoringContext, { timeout: 1000 });
const scoringFixture = () => JSON.parse(vm.runInContext('JSON.stringify(scoringFixture())', scoringContext));

{
  const fixture = scoringFixture();
  // A complete baseline says every starter appeared. Only remove one live row.
  for (const row of fixture.live.elements) {
    if (row.id <= 11) Object.assign(row.stats, { minutes: 90, played: true, total_points: 5 });
  }
  assert.equal(resolveFplScoring(fixture).projected_automatic_subs.length, 0);
  fixture.live.elements = fixture.live.elements.filter(row => row.id !== 1);
  const observed = resolveFplScoring(fixture).projected_automatic_subs;
  results.push({ id: 'missing-live-row', expected: 'Unknown starter appearance must not become a confirmed absence',
    observed, pass: observed.length === 0 });
}

const { default: worker } = await import(pathToFileURL(path.join(root, 'web/workers/playback/src/index.js')));
const originalFetch = globalThis.fetch;
let simulatedModelCalls = 0;
let blockedOfficialCalls = 0;
globalThis.fetch = async input => {
  const url = typeof input === 'string' ? input : input.url;
  if (url === 'https://api.deepseek.com/chat/completions') {
    simulatedModelCalls++;
    return Response.json({ model: 'audit-stub', usage: { total_tokens: 100 }, choices: [{
      finish_reason: 'stop', message: { content: JSON.stringify({
        answer: 'Your current total is 99 points.', confidence: 'high',
        evidence: ['Synthetic fixture only'], assumptions: ['Synthetic fixture only'],
        actions: ['Check official FPL'],
      }) },
    }] });
  }
  blockedOfficialCalls++;
  throw new Error(`Offline audit: all other fetches blocked`);
};
function request(body) {
  return new Request('https://audit.invalid/api/fpl/coach', { method: 'POST',
    headers: { 'content-type': 'application/json', 'x-fotty-install-id': 'audit-install-12345' },
    body: JSON.stringify(body) });
}
try {
  const response = await worker.fetch(request({ query: 'How many gameweek points do I have?', managerId: 12345 }),
    { DEEPSEEK_API_KEY: 'audit-stub-not-a-real-key' });
  const body = await response.json();
  results.push({ id: 'scoring-refresh-failure', expected: 'No model call to calculate points without verified scoring',
    observed: { status: response.status, simulatedModelCalls, source: body.source,
      officialDataStatus: body.officialDataStatus, answer: body.answer }, pass: simulatedModelCalls === 0 });
  let invalid;
  try { invalid = { status: (await worker.fetch(request(null), {})).status }; }
  catch (error) { invalid = { thrown: error.name, message: error.message }; }
  results.push({ id: 'null-request-body', expected: 'Controlled 400 response', observed: invalid, pass: invalid.status === 400 });
} finally {
  globalThis.fetch = originalFetch;
}
console.log(JSON.stringify({ network: { actualNetworkCalls: 0, blockedOfficialCalls, simulatedModelCalls },
  results, violatedExpectations: results.filter(row => !row.pass).length }, null, 2));
process.exitCode = results.some(row => !row.pass) ? 1 : 0;
