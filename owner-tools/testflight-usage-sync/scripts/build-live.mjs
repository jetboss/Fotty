import { cp, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const scriptRoot = dirname(fileURLToPath(import.meta.url));
const toolRoot = resolve(scriptRoot, "..");
const dashboardRoot = resolve(toolRoot, "../testflight-usage-dashboard");
const liveSnapshot = resolve(toolRoot, ".local/testflight-usage.json");
const authoredData = resolve(dashboardRoot, "src/data.json");
const backup = resolve(toolRoot, ".local/authored-data.backup.json");
const defaultBuilder = resolve(process.env.HOME ?? "", ".codex/plugins/cache/openai-curated-remote/data-analytics/1.0.9/scripts/data-app.mjs");
const builder = resolve(process.env.DATA_APP_BUILDER ?? defaultBuilder);

await readFile(liveSnapshot, "utf8");
await cp(authoredData, backup);
let restored = false;
const restore = async () => {
  if (restored) return;
  restored = true;
  await rename(backup, authoredData);
};

try {
  const live = JSON.parse(await readFile(liveSnapshot, "utf8"));
  live.buildStatus = "complete";
  await writeFile(authoredData, `${JSON.stringify(live, null, 2)}\n`);
  const exitCode = await new Promise((resolveExit, reject) => {
    const child = spawn(process.execPath, [builder, "build", "--project-dir", dashboardRoot, "--separate-data"], { stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code, signal) => signal ? reject(new Error(`Dashboard build stopped by ${signal}.`)) : resolveExit(code ?? 1));
  });
  if (exitCode !== 0) throw new Error(`Dashboard build failed with exit code ${exitCode}.`);
} finally {
  await restore();
}

process.stdout.write("Built the private live dashboard. The tracked fixture was restored.\n");
