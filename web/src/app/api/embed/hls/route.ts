import { NextResponse } from "next/server";
import { assertWatchAccess } from "@/lib/server/watch-access";
import { isLocalAuthEnabled } from "@/lib/server/local-auth";

export const dynamic = "force-dynamic";

const EXPOSESTRAT_ORIGIN = "https://exposestrat.com";
const IOS_SAFARI_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const DEFAULT_HLS_HOST_SUFFIXES = ["exposestrat.com", "embedhd.org", "cloudfront.net"];

function allowedHlsHostSuffixes() {
  const configured = (process.env.FOTTY_EMBED_HLS_ALLOWED_HOSTS || "")
    .split(",")
    .map((value) => value.trim().toLowerCase().replace(/^\./, ""))
    .filter(Boolean);
  return new Set([...DEFAULT_HLS_HOST_SUFFIXES, ...configured]);
}

function hostMatchesSuffix(host: string, suffix: string) {
  return host === suffix || host.endsWith(`.${suffix}`);
}

function isSameOriginEmbedReferer(request: Request) {
  const referer = request.headers.get("referer");
  if (!referer) return false;
  try {
    const ref = new URL(referer);
    const req = new URL(request.url);
    return (
      ref.origin === req.origin &&
      (ref.pathname.startsWith("/watch/") ||
        ref.pathname.startsWith("/api/embed/player") ||
        ref.pathname.startsWith("/api/embed/hls"))
    );
  } catch {
    return false;
  }
}

function isAllowedHlsTarget(url: URL) {
  if (url.protocol !== "https:" || url.username || url.password) return false;
  const host = url.hostname.toLowerCase();
  return Array.from(allowedHlsHostSuffixes()).some((suffix) => hostMatchesSuffix(host, suffix));
}

function shouldProxyMediaUrl(url: string) {
  try {
    return isAllowedHlsTarget(new URL(url));
  } catch {
    return false;
  }
}

function proxyMediaPath(absoluteUrl: string, watchToken?: string | null) {
  const params = new URLSearchParams({ url: absoluteUrl });
  if (watchToken) params.set("watchToken", watchToken);
  return `/api/embed/hls?${params.toString()}`;
}

function absolutizeMediaRef(ref: string, manifestUrl: URL) {
  if (/^https?:\/\//i.test(ref)) return ref;
  return new URL(ref, manifestUrl).toString();
}

function rewriteM3u8Playlist(body: string, manifestUrl: URL, watchToken?: string | null) {
  return body
    .split("\n")
    .map((line) => {
      let rewritten = line;

      if (line.includes('URI="')) {
        rewritten = rewritten.replace(/URI="([^"]+)"/g, (_match, uri: string) => {
          try {
            const absolute = absolutizeMediaRef(uri, manifestUrl);
            if (!shouldProxyMediaUrl(absolute)) return `URI="${uri}"`;
            return `URI="${proxyMediaPath(absolute, watchToken)}"`;
          } catch {
            return `URI="${uri}"`;
          }
        });
      }

      const trimmed = rewritten.trim();
      if (!trimmed || trimmed.startsWith("#")) return rewritten;

      let absolute = trimmed;
      if (!/^https?:\/\//i.test(trimmed)) {
        try {
          absolute = new URL(trimmed, manifestUrl).toString();
        } catch {
          return rewritten;
        }
      }

      if (!shouldProxyMediaUrl(absolute)) return absolute;
      return proxyMediaPath(absolute, watchToken);
    })
    .join("\n");
}

function isManifestUrl(url: URL, contentType: string | null) {
  if (url.pathname.toLowerCase().endsWith(".m3u8")) return true;
  const type = contentType?.toLowerCase() || "";
  return type.includes("mpegurl") || type.includes("m3u8");
}

export async function GET(request: Request) {
  const allowLocalWatchReferer = isLocalAuthEnabled() && isSameOriginEmbedReferer(request);
  if (!allowLocalWatchReferer) {
    const denied = await assertWatchAccess(request);
    if (denied) return denied;
  }

  const { searchParams } = new URL(request.url);
  const target = searchParams.get("url")?.trim();
  const watchToken = searchParams.get("watchToken");
  if (!target) {
    return NextResponse.json({ error: "Missing url" }, { status: 400 });
  }

  let targetUrl: URL;
  try {
    targetUrl = new URL(target);
  } catch {
    return NextResponse.json({ error: "Invalid url" }, { status: 400 });
  }

  if (!isAllowedHlsTarget(targetUrl)) {
    return NextResponse.json({ error: "HLS target not allowed" }, { status: 400 });
  }

  const upstream = await fetch(targetUrl.toString(), {
    headers: {
      Accept: "*/*",
      "User-Agent": IOS_SAFARI_USER_AGENT,
      Referer: `${EXPOSESTRAT_ORIGIN}/`,
      Origin: EXPOSESTRAT_ORIGIN,
    },
    cache: "no-store",
  });

  if (!upstream.ok) {
    return NextResponse.json(
      { error: `Upstream HLS request failed (${upstream.status})` },
      { status: upstream.status }
    );
  }

  const contentType = upstream.headers.get("content-type");
  if (isManifestUrl(targetUrl, contentType)) {
    const body = rewriteM3u8Playlist(await upstream.text(), targetUrl, watchToken);
    return new NextResponse(body, {
      status: 200,
      headers: {
        "Content-Type": contentType || "application/vnd.apple.mpegurl",
        "Cache-Control": "no-store",
      },
    });
  }

  const body = await upstream.arrayBuffer();
  return new NextResponse(body, {
    status: 200,
    headers: {
      "Content-Type": contentType || "application/octet-stream",
      "Cache-Control": "no-store",
    },
  });
}
