/** Map PocketBase API error payloads to user-facing copy. */
export function pocketBaseUserMessage(payload: unknown, fallback: string): string {
  if (!payload || typeof payload !== "object") return fallback;

  const root = payload as Record<string, unknown>;
  const data = root.data;
  if (data && typeof data === "object") {
    for (const [fieldName, field] of Object.entries(data as Record<string, unknown>)) {
      if (!field || typeof field !== "object") continue;
      const message = (field as { message?: unknown }).message;
      if (typeof message !== "string" || !message.trim()) continue;
      if (/already in use|invalid or already/i.test(message)) {
        return "An account with this email already exists. Sign in instead, or use Forgot password if you do not remember it.";
      }
      return `${fieldName}: ${message.trim()}`;
    }
  }

  const top = root.message;
  if (typeof top === "string" && /failed to authenticate/i.test(top)) {
    return "PocketBase rejected that password. Type it manually (Safari autofill often inserts a different saved password), or sign out in the Fotty iOS app and sign in there again to confirm it still works.";
  }
  if (typeof top === "string" && top.trim() && !/^Failed to create/i.test(top)) {
    return top.trim();
  }

  return fallback;
}
