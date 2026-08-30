import { NextResponse } from "next/server";
import { assertWatchAccess } from "@/lib/server/watch-access";
import { isLocalAuthEnabled } from "@/lib/server/local-auth";
import { buildProxiedEmbedPlayerHtml } from "@/lib/server/embed-player-proxy";

export const dynamic = "force-dynamic";

function isSameOriginEmbedReferer(request: Request) {
  const referer = request.headers.get("referer");
  if (!referer) return false;
  try {
    const ref = new URL(referer);
    const req = new URL(request.url);
    return (
      ref.origin === req.origin &&
      (ref.pathname.startsWith("/watch/") || ref.pathname.startsWith("/api/embed/player"))
    );
  } catch {
    return false;
  }
}

export async function GET(request: Request) {
  const allowLocalWatchReferer = isLocalAuthEnabled() && isSameOriginEmbedReferer(request);
  if (!allowLocalWatchReferer) {
    const denied = await assertWatchAccess(request);
    if (denied) return denied;
  }

  const { searchParams } = new URL(request.url);
  const source = searchParams.get("source")?.trim();
  const id = searchParams.get("id")?.trim();
  const streamNo = Number(searchParams.get("streamNo") || "1");

  if (!source || !id || !Number.isFinite(streamNo) || streamNo < 1) {
    return NextResponse.json({ error: "Missing source, id, or streamNo" }, { status: 400 });
  }

  const html = await buildProxiedEmbedPlayerHtml(
    source,
    id,
    streamNo,
    searchParams.get("watchToken")?.trim() || undefined,
    request.headers.get("user-agent")?.trim() || undefined
  );
  if (!html) {
    return NextResponse.json({ error: "Could not prepare embed player" }, { status: 502 });
  }

  const frameAncestors = [
    "'self'",
    "https://getfotty.com",
    "https://www.getfotty.com",
    ...(process.env.FOTTY_EMBED_FRAME_ANCESTORS || "")
      .split(/\s+/)
      .map((value) => value.trim())
      .filter(Boolean),
  ].join(" ");

  return new NextResponse(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      // No CSP sandbox — providers reject sandboxed embeds ("SANDBOX IFRAME NOT ALLOWED").
      "Content-Security-Policy": `frame-ancestors ${frameAncestors}`,
      "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
