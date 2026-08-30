#!/usr/bin/env node
/**
 * Copies FOOTBALL_DATA_API_KEY into web/.env.local from the Android project's
 * gitignored local.properties file.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const androidLocalProperties = join(root, "..", "FottyAndroid", "local.properties");
const envLocal = join(root, ".env.local");
const envExample = join(root, ".env.example");

if (!existsSync(androidLocalProperties)) {
  console.error(`Missing ${androidLocalProperties}; copy local.properties.example and add FOOTBALL_DATA_API_KEY.`);
  process.exit(1);
}

const propertiesText = readFileSync(androidLocalProperties, "utf8");
const match = propertiesText.match(/^FOOTBALL_DATA_API_KEY\s*=\s*(.+)$/m);
if (!match?.[1]) {
  console.error("Could not read FOOTBALL_DATA_API_KEY from FottyAndroid/local.properties");
  process.exit(1);
}

const key = match[1].trim();
const line = `FOOTBALL_DATA_API_KEY=${key}`;

if (!existsSync(envLocal)) {
  if (existsSync(envExample)) {
    writeFileSync(envLocal, readFileSync(envExample, "utf8").trimEnd() + "\n");
  } else {
    writeFileSync(envLocal, "");
  }
}

let env = readFileSync(envLocal, "utf8");
if (/^FOOTBALL_DATA_API_KEY=/m.test(env)) {
  env = env.replace(/^FOOTBALL_DATA_API_KEY=.*$/m, line);
} else {
  env = env.trimEnd() + (env.endsWith("\n") ? "" : "\n") + `\n${line}\n`;
}

writeFileSync(envLocal, env);
console.log(`Updated ${envLocal} with FOOTBALL_DATA_API_KEY`);
