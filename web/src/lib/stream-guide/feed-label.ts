import { fottyFeedLabel } from "@/lib/watch-stream-display";
import type { StreamSource } from "@/lib/stream-guide/types";

/**
 * User-facing feed label aligned with iOS source titles (StreamEx #N / Score808 #N).
 */
export function formatStreamFeedLabel(source: StreamSource, index: number) {
  const fromSource = source.displayName?.trim();
  if (fromSource && !/^Fotty\s+\d+$/i.test(fromSource) && fromSource !== "Best Stream") {
    if (source.quality && source.quality !== "Auto" && !fromSource.includes(source.quality)) {
      return `${fromSource} · ${source.quality}`;
    }
    return fromSource;
  }
  const numbered = fottyFeedLabel(index);
  if (source.quality && source.quality !== "Auto") {
    return `${numbered} · ${source.quality}`;
  }
  return numbered;
}

export function eventSourceDisplayName(sourceCode: string | undefined, streamNo: number) {
  const code = (sourceCode || "").trim().toLowerCase();
  const name =
    code === "admin"
      ? "StreamEx PPV"
      : code === "hotel"
        ? "Score808"
        : code === "delta"
          ? "StreamEx"
          : code === "echo"
            ? "VipLeague"
            : code === "golf"
              ? "MethStreams"
              : code === "india"
                ? "StrikeOut"
                : "Fotty";
  return `${name} #${Math.max(1, streamNo || 1)}`;
}
