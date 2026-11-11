import type { EventStreamVariant } from "@/lib/api";

const DEFAULT_EMBED_ORIGIN = "https://embed.st";

/** Canonical StreameX embed URL used when upstream lookup is empty but source/id are known. */
export function buildDirectEmbedUrl(source: string, id: string, streamNo = 1, origin = DEFAULT_EMBED_ORIGIN) {
  const sourcePart = encodeURIComponent(source.trim());
  const idPart = encodeURIComponent(id.trim());
  return `${origin}/embed/${sourcePart}/${idPart}/${Math.max(1, streamNo)}`;
}

/**
 * Browser iframe src for event embeds.
 * Keep direct embed.st (StreamEx works with referrerPolicy=no-referrer).
 * data: host-frames do not give score808live.tv origin — leave Safari-parity to iOS WKWebView.
 */
export function resolveEventEmbedIframeSrc(embedUrl: string): string {
  return embedUrl.trim();
}

export function synthesizeEventStreamVariants(
  source: string,
  id: string,
  feedCount = 1
): EventStreamVariant[] {
  const count = Math.max(1, Math.min(feedCount, 4));
  return Array.from({ length: count }, (_, index) => ({
    id,
    source,
    streamNo: index + 1,
    language: "",
    hd: true,
    embedUrl: buildDirectEmbedUrl(source, id, index + 1),
    viewers: 0,
    provider: "Fotty Live",
    heatTier: "synthesized",
  }));
}

export function firstPlayableEventStream(streams: EventStreamVariant[]) {
  return streams.find((stream) => stream.embedUrl?.trim()) ?? null;
}
