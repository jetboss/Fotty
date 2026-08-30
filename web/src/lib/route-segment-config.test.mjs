import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const webRoot = join(dirname(fileURLToPath(import.meta.url)), "../..");

const DYNAMIC_DATA_ROUTES = [
  "src/app/api/live/streams/route.ts",
  "src/app/api/football/matches/route.ts",
];

test("live-data API routes stay force-dynamic in source", () => {
  const configSource = readFileSync(join(webRoot, "src/lib/route-segment-config.ts"), "utf8");
  const patchScript = readFileSync(join(webRoot, "scripts/patch-watch-routes-static.sh"), "utf8");
  const dockerfile = readFileSync(join(webRoot, "Dockerfile"), "utf8");

  assert.doesNotMatch(
    dockerfile,
    /patch-watch-routes-dynamic/,
    "Docker image must not sed-patch routes; source is already force-dynamic"
  );

  assert.match(
    patchScript,
    /find "\$ROOT\/src\/app\/api" -name 'route\.ts' -print0/,
    "Static-export patching must discover every API route instead of maintaining a second route list"
  );
  assert.match(
    patchScript,
    /force-dynamic.*force-static/,
    "Static-export patching must convert force-dynamic routes for the temporary export build"
  );

  for (const relativePath of DYNAMIC_DATA_ROUTES) {
    const escapedPath = relativePath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    assert.match(configSource, new RegExp(escapedPath));

    const source = readFileSync(join(webRoot, relativePath), "utf8");
    assert.match(
      source,
      /export const dynamic = "force-dynamic"/,
      `${relativePath} must export force-dynamic for standalone builds`
    );
    assert.doesNotMatch(
      source,
      /export const dynamic = "force-static"/,
      `${relativePath} must not keep force-static in source (static export patches separately)`
    );
  }
});
