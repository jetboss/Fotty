/** Use the provider URL as-is inside Fotty's iframe (autoplay query params often break HLS startup). */
export function embedUrlForIframe(raw: string): string {
  return raw.trim();
}

/** Best-effort autoplay hints when opening the provider feed in a new tab. */

export function embedUrlWithAutoplay(raw: string): string {
  try {
    const url = new URL(raw);
    if (!url.searchParams.has("autoplay")) url.searchParams.set("autoplay", "1");
    if (!url.searchParams.has("autoPlay")) url.searchParams.set("autoPlay", "1");
    return url.toString();
  } catch {
    const joiner = raw.includes("?") ? "&" : "?";
    return `${raw}${joiner}autoplay=1`;
  }
}
