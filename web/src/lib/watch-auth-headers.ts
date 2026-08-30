import { getAuthSession } from "@/lib/auth";

/** Headers for protected watch/stream API routes (server verifies entitlement). */
export function getWatchAuthHeaders(): Record<string, string> {
  const session = getAuthSession();
  if (!session?.email) return {};

  const headers: Record<string, string> = {
    "X-Fotty-Email": session.email,
  };

  if (session.userID) {
    headers["X-Fotty-User-Id"] = session.userID;
  }
  if (session.token) {
    headers.Authorization = session.token.startsWith("Bearer ") ? session.token : `Bearer ${session.token}`;
  }

  return headers;
}
