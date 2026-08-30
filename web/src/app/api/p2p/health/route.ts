export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getP2PApiBase } from "@/lib/fotty-config";
import { getP2PApiPassword } from "@/lib/server-env";

const API_BASE = getP2PApiBase();
const HEALTH_TIMEOUT_MS = 8000;

function withTrailingSlash(value: string) {
  return value.endsWith("/") ? value : `${value}/`;
}

function p2pProxyURL(cid: string, aceURL: string, apiPassword: string) {
  const url = new URL("/ace/proxy", withTrailingSlash(API_BASE));
  url.searchParams.set("cid", cid);
  url.searchParams.set("api_password", apiPassword);
  url.searchParams.set("url", aceURL);
  return url;
}

function firstMediaLine(manifest: string) {
  return manifest
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line && !line.startsWith("#"));
}

async function fetchText(url: URL | string, signal: AbortSignal) {
  const response = await fetch(url, {
    cache: "no-store",
    signal,
    headers: {
      Accept: "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*",
    },
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  return response.text();
}

async function fetchSegment(url: URL | string, signal: AbortSignal) {
  const response = await fetch(url, {
    cache: "no-store",
    signal,
    headers: { Accept: "video/mp2t,*/*" },
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const bytes = await response.arrayBuffer();
  return bytes.byteLength;
}

export async function GET(request: Request) {
  const apiPassword = getP2PApiPassword();
  const startedAt = Date.now();
  const { searchParams } = new URL(request.url);
  const cid = searchParams.get("id")?.trim() || searchParams.get("cid")?.trim();

  if (!cid) {
    return NextResponse.json({ playable: false, reason: "missing_cid" }, { status: 400 });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), HEALTH_TIMEOUT_MS);

  try {
    const manifestURL = new URL("/proxy/acestream/manifest.m3u8", withTrailingSlash(API_BASE));
    manifestURL.searchParams.set("infohash", cid);
    manifestURL.searchParams.set("api_password", apiPassword);

    const manifest = await fetchText(manifestURL, controller.signal);
    const firstLine = firstMediaLine(manifest);
    if (!firstLine) {
      return NextResponse.json({ playable: false, reason: "empty_manifest", checkedAt: new Date().toISOString() });
    }

    if (firstLine.endsWith(".m3u8")) {
      const nestedManifest = await fetchText(p2pProxyURL(cid, firstLine, apiPassword), controller.signal);
      const segmentLine = firstMediaLine(nestedManifest);
      if (!segmentLine) {
        return NextResponse.json({ playable: false, reason: "empty_variant", checkedAt: new Date().toISOString() });
      }

      const segmentURL = new URL(segmentLine, firstLine);
      const bytes = await fetchSegment(p2pProxyURL(cid, segmentURL.toString(), apiPassword), controller.signal);
      return NextResponse.json({
        playable: bytes > 0,
        kind: "nested-hls",
        bytes,
        latencyMs: Date.now() - startedAt,
        checkedAt: new Date().toISOString(),
      });
    }

    const bytes = await fetchSegment(firstLine, controller.signal);
    return NextResponse.json({
      playable: bytes > 0,
      kind: "direct-hls",
      bytes,
      latencyMs: Date.now() - startedAt,
      checkedAt: new Date().toISOString(),
    });
  } catch (error) {
    return NextResponse.json({
      playable: false,
      reason: error instanceof Error ? error.message : "health_check_failed",
      latencyMs: Date.now() - startedAt,
      checkedAt: new Date().toISOString(),
    });
  } finally {
    clearTimeout(timeout);
  }
}
