import { readFile, rename, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildDashboardSnapshot, createAppStoreConnectToken, fetchTesterUsage } from "./app-store-connect.mjs";

const scriptRoot = dirname(fileURLToPath(import.meta.url));
const toolRoot = resolve(scriptRoot, "..");
const dashboardRoot = resolve(toolRoot, "../testflight-usage-dashboard");
const defaultOutput = resolve(toolRoot, ".local/testflight-usage.json");

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

const output = resolve(argument("--output", defaultOutput));
const appId = argument("--app-id", process.env.APP_STORE_CONNECT_APP_ID);
const issuerId = process.env.APP_STORE_CONNECT_ISSUER_ID;
const keyId = process.env.APP_STORE_CONNECT_KEY_ID;
const privateKeyPath = process.env.APP_STORE_CONNECT_PRIVATE_KEY_PATH;

if (!privateKeyPath) throw new Error("APP_STORE_CONNECT_PRIVATE_KEY_PATH is required.");
const privateKey = await readFile(resolve(privateKeyPath), "utf8");
const token = createAppStoreConnectToken({ issuerId, keyId, privateKey });
const rows = await fetchTesterUsage({ appId, token });
const dashboardData = JSON.parse(await readFile(resolve(dashboardRoot, "src/data.json"), "utf8"));
const snapshot = buildDashboardSnapshot({ rows, dashboardId: dashboardData.id });

await mkdir(dirname(output), { recursive: true, mode: 0o700 });
const temporary = `${output}.tmp`;
await writeFile(temporary, `${JSON.stringify(snapshot, null, 2)}\n`, { mode: 0o600 });
await rename(temporary, output);
process.stdout.write(`Saved ${rows.length} tester records to a private local snapshot.\n`);
