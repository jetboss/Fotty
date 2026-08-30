import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import path from "node:path";

const root = process.cwd();
const nextDir = path.join(root, ".next");
const standaloneDir = path.join(nextDir, "standalone");
const standaloneNextDir = path.join(standaloneDir, ".next");
const staticDir = path.join(nextDir, "static");
const standaloneStaticDir = path.join(standaloneNextDir, "static");
const publicDir = path.join(root, "public");
const standalonePublicDir = path.join(standaloneDir, "public");

mkdirSync(standaloneNextDir, { recursive: true });

if (existsSync(staticDir)) {
  rmSync(standaloneStaticDir, { recursive: true, force: true });
  cpSync(staticDir, standaloneStaticDir, { recursive: true });
}

if (existsSync(publicDir)) {
  rmSync(standalonePublicDir, { recursive: true, force: true });
  cpSync(publicDir, standalonePublicDir, { recursive: true });
}

console.log("Standalone assets prepared.");
