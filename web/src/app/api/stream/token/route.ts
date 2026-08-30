import { NextResponse } from "next/server";
import { requireWatchAccess } from "@/lib/server/watch-access";
import {
  issueWatchStreamToken,
  WATCH_STREAM_TOKEN_TTL_SECONDS,
} from "@/lib/server/watch-stream-token";
import { checkRateLimit, clientRateLimitKey, rateLimitResponse } from "@/lib/server/rate-limit";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (!checkRateLimit(clientRateLimitKey(request, "stream-token"), 120, 60_000)) {
    return rateLimitResponse();
  }

  const access = await requireWatchAccess(request);
  if (access instanceof NextResponse) return access;

  const watchToken = issueWatchStreamToken({
    email: access.email,
    userID: access.userID,
    entitlement: access.entitlement,
  });
  if (!watchToken) {
    return NextResponse.json(
      {
        error: "Stream tokens are not configured. Set FOTTY_WATCH_STREAM_SECRET.",
      },
      { status: 503 }
    );
  }

  return NextResponse.json({
    watchToken,
    expiresIn: WATCH_STREAM_TOKEN_TTL_SECONDS,
  });
}
