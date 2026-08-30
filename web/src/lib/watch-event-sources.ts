export interface WatchEventSource {
  source: string;
  id: string;
}

/**
 * Compact serialization for the watch `sources` query param. Source codes are
 * fixed tokens (echo/delta/...) and ids are slugs, so `~`/`,` delimiters are
 * safe and URLSearchParams round-trips the joined string exactly.
 */
export function encodeWatchEventSources(sources: WatchEventSource[]): string {
  return dedupeWatchEventSources(sources)
    .map((entry) => `${entry.source}~${entry.id}`)
    .join(",");
}

export function decodeWatchEventSources(value?: string | null): WatchEventSource[] {
  if (!value) return [];
  const parsed = value
    .split(",")
    .map((part) => {
      const separator = part.indexOf("~");
      if (separator <= 0) return null;
      const source = part.slice(0, separator).trim();
      const id = part.slice(separator + 1).trim();
      if (!source || !id) return null;
      return { source, id };
    })
    .filter((entry): entry is WatchEventSource => entry !== null);
  return dedupeWatchEventSources(parsed);
}

export function dedupeWatchEventSources(sources: WatchEventSource[]): WatchEventSource[] {
  const seen = new Set<string>();
  const result: WatchEventSource[] = [];
  for (const entry of sources) {
    const source = entry.source?.trim();
    const id = entry.id?.trim();
    if (!source || !id) continue;
    const key = `${source}:${id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({ source, id });
  }
  return result;
}

export function watchEventSourcesKey(sources: WatchEventSource[]): string {
  return dedupeWatchEventSources(sources)
    .map((entry) => `${entry.source}:${entry.id}`)
    .join("|");
}
