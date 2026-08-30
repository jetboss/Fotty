// Read-only audit: uses the repository's installed ESLint, no configuration edits.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const require = createRequire(path.join(root, 'web/package.json'));
const { Linter } = require('eslint');
const linter = new Linter();

export function extractMonitor() {
  const file = 'Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift';
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const declaration = source.indexOf('static func playbackMonitorScript(');
  const begin = source.indexOf('        """\n', declaration) + '        """\n'.length;
  const end = source.indexOf('\n        """', begin);
  if (declaration < 0 || end < begin) throw new Error('Monitor boundary not found');
  const policy = source;
  let code = source.slice(begin, end)
    .replace(/\\\((isMuted|providerControlsAudio|isSuspended) \? "true" : "false"\)/g,
      (_, name) => name === 'isSuspended' ? 'false' : 'true')
    .replace(/\\\(Int\(LivePlaybackPolicy\.(webStartupFailureSeconds|webStallFailureSeconds)( \* 1_000)?\)\)/g,
      (_, name, milliseconds) => {
        const match = policy.match(new RegExp(`${name}[^=\\n]*=\\s*([0-9.]+)`));
        if (!match) throw new Error(`Unknown policy: ${name}`);
        return String(Math.trunc(Number(match[1]) * (milliseconds ? 1000 : 1)));
      });
  if (code.includes('\\(')) throw new Error('Unresolved Swift interpolation');
  code = code.replace(/\\\\/g, '\\');
  return { code, file, firstLine: source.slice(0, begin).split('\n').length };
}

function measure({ code, file, firstLine = 1 }) {
  const messages = linter.verify(code, [{
    languageOptions: { ecmaVersion: 'latest', sourceType: 'module' },
    rules: { complexity: ['warn', { max: 0, variant: 'classic' }] },
  }], { filename: 'audit.js' });
  if (messages.some(message => message.fatal || message.ruleId !== 'complexity')) {
    throw new Error(JSON.stringify(messages.filter(message => message.fatal || message.ruleId !== 'complexity')));
  }
  const rows = messages.map(message => ({
    file, line: message.line + firstLine - 1,
    cc: Number(message.message.match(/complexity of (\d+)/)[1]),
    function: message.message.split(' has a complexity')[0],
  }));
  return {
    file, functions: rows.length, over10: rows.filter(row => row.cc > 10).length,
    over20: rows.filter(row => row.cc > 20).length,
    max: Math.max(...rows.map(row => row.cc)),
    hotspots: rows.filter(row => row.cc > 10).sort((a, b) => b.cc - a.cc),
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = ['web/workers/playback/src/index.js', 'web/workers/playback/src/fpl-scoring.mjs'];
  const inputs = files.map(file => ({ file, code: fs.readFileSync(path.join(root, file), 'utf8') }));
  inputs.push(extractMonitor());
  console.log(JSON.stringify({ tool: `ESLint ${Linter.version}`, variant: 'classic',
    results: inputs.map(measure) }, null, 2));
}
