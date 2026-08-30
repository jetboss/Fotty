import { getP2PApiBase } from "@/lib/fotty-config";
import { getP2PApiPassword } from "@/lib/server-env";

const API_BASE = getP2PApiBase();
const SESSION_CREATE_TIMEOUT_MS = 15_000;
const WARM_POLL_INTERVAL_MS = 600;
const DEFAULT_WARM_TIMEOUT_MS = 20_000;
const MIN_SEGMENT_PROBE_BYTES = 1024;

export interface BrokerSessionRecord {
  session_id: string;
  source_id: string;
  state?: string;
  message?: string;
  manifest_url?: string;
  status_url?: string;
  first_segment_ready?: boolean;
  ready_segment_count?: number;
  peer_count?: number;
}

function withTrailingSlash(value: string) {
  return value.endsWith("/") ? value : `${value}/`;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function createBrokerSession(
  cid: string,
  meta?: { title?: string; category?: string; forceNew?: boolean }
): Promise<BrokerSessionRecord> {
  const apiPassword = getP2PApiPassword();
  const url = new URL("/proxy/acestream/session", withTrailingSlash(API_BASE));

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), SESSION_CREATE_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      cache: "no-store",
      body: JSON.stringify({
        cid,
        api_password: apiPassword,
        ...(meta?.title ? { title: meta.title } : {}),
        ...(meta?.category ? { category: meta.category } : {}),
        ...(meta?.forceNew ? { force_new: true } : {}),
        source: "fotty-web",
      }),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new Error(`Broker session failed (${response.status}): ${detail.slice(0, 200)}`);
    }

    return (await response.json()) as BrokerSessionRecord;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchBrokerSessionStatus(sessionId: string): Promise<BrokerSessionRecord | null> {
  const apiPassword = getP2PApiPassword();
  const url = new URL(`/proxy/acestream/session/${sessionId}/status`, withTrailingSlash(API_BASE));
  url.searchParams.set("api_password", apiPassword);

  const response = await fetch(url, { cache: "no-store", headers: { Accept: "application/json" } });
  if (!response.ok) return null;
  return (await response.json()) as BrokerSessionRecord;
}

function firstSegmentRef(manifest: string, manifestURL: URL): string | null {
  for (const raw of manifest.split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    try {
      return new URL(line, manifestURL).href;
    } catch {
      continue;
    }
  }
  return null;
}

async function fetchSessionManifest(sessionId: string): Promise<{ manifest: string; manifestURL: URL } | null> {
  const apiPassword = getP2PApiPassword();
  const manifestURL = new URL(
    `/proxy/acestream/session/${sessionId}/manifest.m3u8`,
    withTrailingSlash(API_BASE)
  );
  manifestURL.searchParams.set("api_password", apiPassword);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);

  try {
    const response = await fetch(manifestURL, {
      cache: "no-store",
      signal: controller.signal,
      headers: {
        Accept: "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*",
      },
    });

    if (!response.ok) return null;
    const manifest = await response.text();
    if (!manifest.includes("#EXTM3U")) return null;
    return { manifest, manifestURL };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function probeBrokerManifest(sessionId: string): Promise<boolean> {
  const fetched = await fetchSessionManifest(sessionId);
  if (!fetched) return false;
  return /\.ts(?:\?|$)/m.test(fetched.manifest) || Boolean(firstSegmentRef(fetched.manifest, fetched.manifestURL));
}

/** iOS AceSessionEngine parity: manifest must list a segment and first bytes must be readable. */
async function probeBrokerSegment(sessionId: string, cid: string): Promise<boolean> {
  const fetched = await fetchSessionManifest(sessionId);
  if (!fetched) return false;

  const segmentRef = firstSegmentRef(fetched.manifest, fetched.manifestURL);
  if (!segmentRef) {
    return /\.ts(?:\?|$)/m.test(fetched.manifest);
  }

  const apiPassword = getP2PApiPassword();
  let fetchURL: URL;
  try {
    const segmentURL = new URL(segmentRef);
    if (segmentURL.hostname === "127.0.0.1") {
      fetchURL = new URL("/ace/proxy", withTrailingSlash(API_BASE));
      fetchURL.searchParams.set("cid", cid);
      fetchURL.searchParams.set("api_password", apiPassword);
      fetchURL.searchParams.set("url", segmentRef);
    } else {
      fetchURL = segmentURL;
      if (!fetchURL.searchParams.has("api_password")) {
        fetchURL.searchParams.set("api_password", apiPassword);
      }
    }
  } catch {
    return false;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);

  try {
    const response = await fetch(fetchURL, {
      cache: "no-store",
      signal: controller.signal,
      headers: {
        Accept: "video/mp2t,*/*",
        Range: "bytes=0-1023",
      },
    });

    if (!response.ok) return false;
    const bytes = await response.arrayBuffer();
    return bytes.byteLength >= MIN_SEGMENT_PROBE_BYTES;
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
  }
}

async function probeBrokerPlayback(sessionId: string, cid: string): Promise<boolean> {
  if (!(await probeBrokerManifest(sessionId))) return false;
  return probeBrokerSegment(sessionId, cid);
}

/** Create a broker session and wait until manifest probe succeeds (iOS PlaybackWarmup parity). */
export async function createAndWarmBrokerSession(
  cid: string,
  meta?: { title?: string; category?: string; forceNew?: boolean },
  warmTimeoutMs = DEFAULT_WARM_TIMEOUT_MS
): Promise<{ session: BrokerSessionRecord; ready: boolean }> {
  const session = await createBrokerSession(cid, meta);
  const sessionId = session.session_id;
  if (!sessionId) {
    throw new Error("Broker session missing session_id");
  }

  const deadline = Date.now() + warmTimeoutMs;
  let latest = session;

  while (Date.now() < deadline) {
    if (await probeBrokerPlayback(sessionId, cid)) {
      return { session: latest, ready: true };
    }

    const status = await fetchBrokerSessionStatus(sessionId);
    if (status) latest = { ...latest, ...status };

    const state = (latest.state || "").toLowerCase();
    if (state === "ready" && (latest.first_segment_ready || (latest.ready_segment_count ?? 0) > 0)) {
      if (await probeBrokerPlayback(sessionId, cid)) {
        return { session: latest, ready: true };
      }
    }

    await sleep(WARM_POLL_INTERVAL_MS);
  }

  return { session: latest, ready: false };
}
