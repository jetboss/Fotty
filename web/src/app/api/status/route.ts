export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getP2PApiBase } from "@/lib/fotty-config";
import { getP2PApiPassword } from "@/lib/server-env";

const API_BASE = getP2PApiBase();

function withTrailingSlash(value: string) {
  return value.endsWith("/") ? value : `${value}/`;
}

function numberFrom(payload: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = payload[key];
    const numberValue = Number(value);
    if (Number.isFinite(numberValue)) return numberValue;
  }

  return 0;
}

function booleanFrom(payload: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    if (typeof payload[key] === "boolean") return payload[key] as boolean;
  }

  return false;
}

function mapBrokerStatus(payload: Record<string, unknown>) {
  const readySegmentCount = numberFrom(payload, ["readySegmentCount", "ready_segment_count", "ready_segments", "readySegments"]);
  const state = typeof payload.state === "string" ? payload.state : undefined;
  const normalizedState = state?.trim().toLowerCase();
  const firstSegmentReady =
    booleanFrom(payload, ["firstSegmentReady", "first_segment_ready"]) ||
    readySegmentCount > 0 ||
    normalizedState === "ready";

  return {
    peerCount: numberFrom(payload, ["peerCount", "peer_count", "peers", "activePeers", "active_peers"]),
    downloadSpeedKbps: numberFrom(payload, ["downloadSpeedKbps", "download_speed_kbps", "download_speed", "speedKbps"]),
    bufferSeconds: numberFrom(payload, ["bufferSeconds", "buffer_seconds", "buffer", "buffer_progress"]),
    readySegmentCount,
    firstSegmentReady,
    clientCount: numberFrom(payload, ["clientCount", "client_count", "clients"]),
    isLive: booleanFrom(payload, ["isLive", "is_live"]),
    status: state,
    error: typeof payload.message === "string" ? payload.message : payload.error,
    raw: payload,
  };
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const cid = searchParams.get("id")?.trim();
  const sessionId = searchParams.get("session")?.trim();

  if (!cid) {
    return NextResponse.json({ error: "Missing CID" }, { status: 400 });
  }

  try {
    const apiPassword = getP2PApiPassword();
    const url = sessionId
      ? new URL(`/proxy/acestream/session/${sessionId}/status`, withTrailingSlash(API_BASE))
      : new URL(`${withTrailingSlash(API_BASE)}proxy/acestream/status`);

    if (sessionId) {
      url.searchParams.set("api_password", apiPassword);
    } else {
      url.searchParams.set("infohash", cid);
      url.searchParams.set("api_password", apiPassword);
    }

    const response = await fetch(url, { cache: "no-store" });

    if (!response.ok) {
      return NextResponse.json({ error: "Status unavailable" }, { status: 503 });
    }

    const payload = (await response.json()) as Record<string, unknown>;
    if (sessionId) {
      return NextResponse.json(mapBrokerStatus(payload));
    }

    const readySegmentCount = numberFrom(payload, ["readySegmentCount", "ready_segments", "readySegments"]);
    const status = typeof payload.status === "string" ? payload.status : undefined;
    const error = status === "not_found" ? "P2P session warming up" : payload.error;

    return NextResponse.json({
      peerCount: numberFrom(payload, ["peerCount", "peer_count", "peers", "activePeers", "active_peers"]),
      downloadSpeedKbps: numberFrom(payload, ["downloadSpeedKbps", "download_speed_kbps", "download_speed", "speedKbps"]),
      bufferSeconds: numberFrom(payload, ["bufferSeconds", "buffer_seconds", "buffer", "buffer_progress"]),
      readySegmentCount,
      firstSegmentReady: booleanFrom(payload, ["firstSegmentReady", "first_segment_ready"]) || readySegmentCount > 0,
      clientCount: numberFrom(payload, ["clientCount", "client_count", "clients"]),
      isLive: booleanFrom(payload, ["isLive", "is_live"]),
      status,
      error,
      raw: payload,
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
