#!/usr/bin/env node
/**
 * Writes web/.env.local from web/.env.example (project defaults).
 * Safe to re-run; does not overwrite an existing .env.local unless --force is passed.
 */

import { copyFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const examplePath = join(webRoot, ".env.example");
const localPath = join(webRoot, ".env.local");
const force = process.argv.includes("--force");

if (existsSync(localPath) && !force) {
  console.log(`skip: ${localPath} already exists (use --force to replace)`);
  process.exit(0);
}

copyFileSync(examplePath, localPath);
console.log(`wrote ${localPath} from .env.example`);
