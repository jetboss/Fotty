import assert from "node:assert/strict";
import test from "node:test";
import {
  decodeWatchEventSources,
  dedupeWatchEventSources,
  encodeWatchEventSources,
  watchEventSourcesKey,
} from "./watch-event-sources.ts";

test("encode and decode round-trip preserves all provider links", () => {
  const sources = [
    { source: "echo", id: "spain-vs-belgium-spanish-12" },
    { source: "delta", id: "spain-vs-belgium-english-34" },
    { source: "golf", id: "spain-vs-belgium-german-56" },
  ];
  const encoded = encodeWatchEventSources(sources);
  assert.equal(
    encoded,
    "echo~spain-vs-belgium-spanish-12,delta~spain-vs-belgium-english-34,golf~spain-vs-belgium-german-56"
  );

  const url = new URLSearchParams();
  url.set("sources", encoded);
  assert.deepEqual(decodeWatchEventSources(url.get("sources")), sources);
});

test("dedupe removes repeated source/id pairs and blanks", () => {
  const deduped = dedupeWatchEventSources([
    { source: "echo", id: "a" },
    { source: "echo", id: "a" },
    { source: " ", id: "b" },
    { source: "delta", id: "" },
    { source: "delta", id: "c" },
  ]);
  assert.deepEqual(deduped, [
    { source: "echo", id: "a" },
    { source: "delta", id: "c" },
  ]);
});

test("decode tolerates malformed entries", () => {
  assert.deepEqual(decodeWatchEventSources(""), []);
  assert.deepEqual(decodeWatchEventSources(null), []);
  assert.deepEqual(decodeWatchEventSources("echo,~orphan,~,echo~ok"), [
    { source: "echo", id: "ok" },
  ]);
});

test("key is stable and deduped", () => {
  const key = watchEventSourcesKey([
    { source: "echo", id: "a" },
    { source: "delta", id: "b" },
    { source: "echo", id: "a" },
  ]);
  assert.equal(key, "echo:a|delta:b");
});
