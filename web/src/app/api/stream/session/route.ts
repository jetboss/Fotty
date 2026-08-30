import { NextResponse } from "next/server";
import { createAndWarmBrokerSession } from "@/lib/server/p2p-broker";
import { assertWatchAccess } from "@/lib/server/watch-access";
import { checkRateLimit, clientRateLimitKey, rateLimitResponse } from "@/lib/server/rate-limit";
import { isP2PConfigured, p2pMisconfiguredResponse } from "@/lib/server-env";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  if (!checkRateLimit(clientRateLimitKey(request, "stream-session"), 40, 60_000)) {
    return rateLimitResponse();
  }

  const denied = await assertWatchAccess(request);
  if (denied) return denied;

  if (!isP2PConfigured()) {
    return p2pMisconfiguredResponse();
  }

  let cid = "";
  let title: string | undefined;
  let forceNew = false;

  try {
    const body = (await request.json()) as { cid?: string; id?: string; title?: string; forceNew?: boolean; force_new?: boolean };
    cid = (body.cid || body.id || "").trim();
    title = body.title?.trim() || undefined;
    forceNew = Boolean(body.forceNew || body.force_new);
  } catch {
    const { searchParams } = new URL(request.url);
    cid = searchParams.get("cid")?.trim() || searchParams.get("id")?.trim() || "";
    title = searchParams.get("title")?.trim() || undefined;
    forceNew = ["1", "true", "yes"].includes((searchParams.get("forceNew") || searchParams.get("force_new") || "").toLowerCase());
  }

  if (!cid) {
    return NextResponse.json({ error: "Missing CID" }, { status: 400 });
  }

  try {
    const { session, ready } = await createAndWarmBrokerSession(
      cid,
      { title, forceNew },
      22_000
    );
    const state = session.state || (ready ? "ready" : "warming");

    return NextResponse.json({
      sessionId: session.session_id,
      cid: session.source_id || cid,
      ready,
      state: ready ? "ready" : state,
      message: ready ? session.message || "Playable stream is ready." : session.message || "Checking stream signal…",
      peerCount: session.peer_count ?? 0,
      readySegmentCount: session.ready_segment_count ?? 0,
      firstSegmentReady: Boolean(session.first_segment_ready) || ready,
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Broker session failed" },
      { status: 502 }
    );
  }
}
