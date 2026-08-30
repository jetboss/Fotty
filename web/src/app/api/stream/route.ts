export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getP2PApiBase, getPublicP2POrigin } from "@/lib/fotty-config";
import { getP2PApiPassword, isP2PConfigured, p2pMisconfiguredResponse } from "@/lib/server-env";
import { assertWatchAccess } from "@/lib/server/watch-access";
import { issuePublicP2PStreamToken } from "@/lib/server/public-p2p-stream-token";

function withTrailingSlash(value: string) {
  return value.endsWith("/") ? value : `${value}/`;
}

function rewriteManifestCredentials(manifest: string, publicToken: string) {
  const publicOrigin = getPublicP2POrigin();
  return manifest
    .split("\n")
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) return line;
      try {
        const target = new URL(trimmed);
        if (target.origin !== publicOrigin) return line;
        target.searchParams.delete("api_password");
        target.searchParams.set("stream_token", publicToken);
        return target.toString();
      } catch {
        return line;
      }
    })
    .join("\n");
}

async function fetchManifest(target: URL) {
  return fetch(target, {
    cache: "no-store",
    headers: {
      Accept: "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*",
    },
    signal: AbortSignal.timeout(30_000),
  });
}

export async function GET(request: Request) {
  const denied = await assertWatchAccess(request);
  if (denied) return denied;

  if (!isP2PConfigured()) {
    return p2pMisconfiguredResponse();
  }

  const { searchParams } = new URL(request.url);
  const cid = searchParams.get("id")?.trim() || searchParams.get("infohash")?.trim();
  const sessionId = searchParams.get("session")?.trim();

  if (!cid) {
    return NextResponse.json({ error: "Missing CID" }, { status: 400 });
  }

  const apiPassword = getP2PApiPassword();
  const apiBase = withTrailingSlash(getP2PApiBase());
  const publicToken = issuePublicP2PStreamToken(cid);
  if (!publicToken) {
    return NextResponse.json({ error: "Direct stream tokens are not configured." }, { status: 503 });
  }

  let upstream: Response | null = null;
  if (sessionId) {
    const manifestURL = new URL(`/proxy/acestream/session/${sessionId}/manifest.m3u8`, apiBase);
    manifestURL.searchParams.set("api_password", apiPassword);
    try {
      upstream = await fetchManifest(manifestURL);
    } catch {
      upstream = null;
    }
  }

  // A session can report ready just before its cached playlist freezes. Fall
  // back to the CID-bound public route so HLS.js can recover without exposing
  // the broker password or forcing the user to restart playback.
  if (!upstream?.ok) {
    const streamURL = new URL("/proxy/acestream/stream", getPublicP2POrigin());
    streamURL.searchParams.set("id", cid);
    streamURL.searchParams.set("stream_token", publicToken);
    try {
      upstream = await fetchManifest(streamURL);
    } catch {
      upstream = null;
    }
  }

  if (!upstream?.ok) {
    return NextResponse.json(
      { error: "The stream manifest is still preparing." },
      { status: upstream?.status || 504 }
    );
  }

  const manifest = rewriteManifestCredentials(await upstream.text(), publicToken);
  return new NextResponse(manifest, {
    status: 200,
    headers: {
      "Content-Type": "application/vnd.apple.mpegurl; charset=utf-8",
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      Pragma: "no-cache",
    },
  });
}
