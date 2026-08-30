import { NextResponse } from "next/server";
import { getP2PApiBase, getPublicP2POrigin } from "@/lib/fotty-config";
import { getP2PApiPassword, isP2PConfigured, p2pMisconfiguredResponse } from "@/lib/server-env";
import { assertWatchAccess } from "@/lib/server/watch-access";
import { checkRateLimit, clientRateLimitKey, rateLimitResponse } from "@/lib/server/rate-limit";

export const dynamic = "force-dynamic";

const API_BASE = getP2PApiBase();
const SEGMENT_TIMEOUT_MS = 30000;

function isAllowedAceURL(value: string, cid: string) {
  try {
    const url = new URL(value);
    const allowedPath =
      (url.pathname.startsWith(`/ace/c/${cid}/`) && url.pathname.endsWith(".ts")) ||
      (url.pathname.startsWith(`/hls/c/${cid}/`) && url.pathname.endsWith(".ts")) ||
      (url.pathname.startsWith(`/hls/m/${cid}/`) && url.pathname.endsWith(".m3u8"));
    return url.protocol === "http:" && url.host === "127.0.0.1:6878" && allowedPath;
  } catch {
    return false;
  }
}

function isBrokerAceProxyUrl(url: URL) {
  try {
    return url.origin === getPublicP2POrigin() && url.pathname.includes("/ace/proxy");
  } catch {
    return false;
  }
}

function rewriteNestedManifest(manifest: string, request: Request, cid: string, baseAceURL: string) {
  const watchToken = new URL(request.url).searchParams.get("watchToken");
  return manifest
    .split("\n")
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) return line;

      try {
        const absoluteAceURL = new URL(trimmed, baseAceURL);
        if (isBrokerAceProxyUrl(absoluteAceURL)) {
          return absoluteAceURL.toString();
        }
        const target = new URL("/api/stream/segment", request.url);
        target.searchParams.set("cid", cid);
        target.searchParams.set("url", absoluteAceURL.toString());
        if (watchToken) target.searchParams.set("watchToken", watchToken);
        return `${target.pathname}${target.search}`;
      } catch {
        return line;
      }
    })
    .join("\n");
}

export async function GET(request: Request) {
  if (!checkRateLimit(clientRateLimitKey(request, "stream-segment"), 600, 60_000)) {
    return rateLimitResponse();
  }

  const denied = await assertWatchAccess(request);
  if (denied) return denied;

  if (!isP2PConfigured()) {
    return p2pMisconfiguredResponse();
  }

  const apiPassword = getP2PApiPassword();
  const { searchParams } = new URL(request.url);
  const cid = searchParams.get("cid")?.trim();
  const aceURL = searchParams.get("url")?.trim();

  if (!cid || !aceURL || !isAllowedAceURL(aceURL, cid)) {
    return NextResponse.json({ error: "Invalid segment target" }, { status: 400 });
  }

  const target = new URL("/ace/proxy", API_BASE.endsWith("/") ? API_BASE : `${API_BASE}/`);
  target.searchParams.set("cid", cid);
  target.searchParams.set("api_password", apiPassword);
  target.searchParams.set("url", aceURL);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), SEGMENT_TIMEOUT_MS);
  const range = request.headers.get("range");

  try {
    const upstream = await fetch(target, {
      cache: "no-store",
      signal: controller.signal,
      headers: {
        Accept: "video/mp2t,*/*",
        ...(range ? { Range: range } : {}),
      },
    });

    if (!upstream.ok || !upstream.body) {
      return NextResponse.json({ error: "P2P segment unavailable" }, { status: upstream.status || 502 });
    }

    const contentType = upstream.headers.get("content-type") || "";
    if (contentType.includes("mpegurl") || aceURL.endsWith(".m3u8")) {
      const manifest = await upstream.text();
      return new NextResponse(rewriteNestedManifest(manifest, request, cid, aceURL), {
        status: 200,
        headers: {
          "Content-Type": "application/vnd.apple.mpegurl; charset=utf-8",
          "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
          Pragma: "no-cache",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    const headers = new Headers({
      "Content-Type": upstream.headers.get("content-type") || "video/mp2t",
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      Pragma: "no-cache",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges",
    });
    for (const header of ["content-length", "content-range", "accept-ranges"]) {
      const value = upstream.headers.get(header);
      if (value) headers.set(header, value);
    }

    return new NextResponse(upstream.body, {
      status: upstream.status,
      headers,
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "P2P segment failed" }, { status: 504 });
  } finally {
    clearTimeout(timeout);
  }
}
