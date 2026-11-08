import assert from "node:assert/strict";
import test from "node:test";

import {
  supportedUCLSourceCodes,
  usableWorkerVariantCount,
} from "./audit-ucl-readiness-policy.mjs";

test("the readiness policy includes every catalog source accepted by playback", () => {
  assert.ok(supportedUCLSourceCodes.includes("admin"));
  assert.ok(supportedUCLSourceCodes.includes("hotel"));
});

test("a synthetic Worker legacy route is not proof of provider readiness", () => {
  assert.equal(usableWorkerVariantCount([{
    embedUrl: "https://embed.st/embed/delta/example/1",
    provider: "Legacy",
    heatTier: "legacy",
  }]), 0);
});

test("only concrete HTTPS provider variants count as usable", () => {
  assert.equal(usableWorkerVariantCount({ streams: [
    { embedUrl: "https://embed.st/embed/admin/example/1", provider: "StreameX" },
    { embedUrl: "", provider: "StreameX" },
    { embedUrl: "javascript:alert(1)", provider: "StreameX" },
    null,
  ] }), 1);
});
