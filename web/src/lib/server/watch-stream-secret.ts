/** Dedicated secret for short-lived HLS watch tokens — not shared with billing webhooks. */

export function getWatchStreamSecret(): string {
  return process.env.FOTTY_WATCH_STREAM_SECRET?.trim() || "";
}

export function isWatchStreamSecretConfigured(): boolean {
  return Boolean(getWatchStreamSecret());
}
