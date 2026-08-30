import { NextResponse } from "next/server";
import { getPublicP2POrigin } from "@/lib/fotty-config";
import { isP2PConfigured, p2pMisconfiguredResponse } from "@/lib/server-env";
import { issuePublicP2PStreamToken } from "@/lib/server/public-p2p-stream-token";
import { checkRateLimit, clientRateLimitKey, rateLimitResponse } from "@/lib/server/rate-limit";
import { assertWatchAccess } from "@/lib/server/watch-access";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (!checkRateLimit(clientRateLimitKey(request, "stream-native"), 120, 60_000)) {
    return rateLimitResponse();
  }

  const denied = await assertWatchAccess(request);
  if (denied) return denied;

  if (!isP2PConfigured()) {
    return p2pMisconfiguredResponse();
  }

  const { searchParams } = new URL(request.url);
  const cid = searchParams.get("id")?.trim() || searchParams.get("infohash")?.trim();
  if (!cid) {
    return NextResponse.json({ error: "Missing CID" }, { status: 400 });
  }

  const streamToken = issuePublicP2PStreamToken(cid);
  if (!streamToken) {
    return NextResponse.json({ error: "Direct stream tokens are not configured." }, { status: 503 });
  }

  const target = new URL("/proxy/acestream/stream", getPublicP2POrigin());
  target.searchParams.set("id", cid);
  target.searchParams.set("stream_token", streamToken);

  const response = NextResponse.redirect(target, 307);
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  response.headers.set("Pragma", "no-cache");
  return response;
}
