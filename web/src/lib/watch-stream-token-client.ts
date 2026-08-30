import { getWatchAuthHeaders } from "@/lib/watch-auth-headers";
import { fetchFottyApi } from "@/lib/fotty-api-fetch";

let cachedToken: { value: string; expiresAt: number } | null = null;

/** Shared short-lived HLS/embed token — one fetch for streams lookup + player iframe. */
export async function fetchWatchStreamToken(force = false): Promise<string | null> {
  if (!force && cachedToken && Date.now() < cachedToken.expiresAt - 60_000) {
    return cachedToken.value;
  }

  try {
    const response = await fetchFottyApi("/api/stream/token", {
      headers: { Accept: "application/json", ...getWatchAuthHeaders() },
      cache: "no-store",
    });
    if (!response.ok) return null;

    const payload = (await response.json().catch(() => ({}))) as {
      watchToken?: string;
      expiresIn?: number;
    };
    if (!payload.watchToken) return null;

    const ttlMs = (payload.expiresIn ?? 10 * 60) * 1000;
    cachedToken = { value: payload.watchToken, expiresAt: Date.now() + ttlMs };
    return payload.watchToken;
  } catch {
    return null;
  }
}

export function invalidateWatchStreamTokenCache() {
  cachedToken = null;
}
