/**
 * Pure helpers for event-embed failover. Keep timer/UI effects in the watch hook.
 */

export type EventGuideSource = {
  id?: string;
  eventIndex?: number;
  diagnosticsSafeId?: string;
};

export type EventStreamGuide = {
  all: EventGuideSource[];
  recommended?: EventGuideSource | null;
};

export function markFailedEventSource(
  failedIds: Set<string>,
  source: EventGuideSource | undefined
): Set<string> {
  const next = new Set(failedIds);
  if (source?.id) next.add(source.id);
  return next;
}

export function resolveEventBackupIndex<G extends EventStreamGuide>(
  guide: G | null | undefined,
  selectedIndex: number,
  failedIds: Set<string>,
  pickBackup: (
    guide: G,
    failedSourceId?: string,
    alsoFailed?: Iterable<string>
  ) => G["all"][number] | null | undefined
): { nextIndex: number; backup: G["all"][number] } | null {
  if (!guide) return null;
  const failed = guide.all.find((source) => source.eventIndex === selectedIndex);
  const withFailed = markFailedEventSource(failedIds, failed);
  const backup = pickBackup(guide, failed?.id, withFailed);
  if (backup?.eventIndex === undefined || backup.eventIndex === selectedIndex) {
    return null;
  }
  return { nextIndex: backup.eventIndex, backup };
}

export function shouldArmEmbedLoadTimeout(input: {
  useEventEmbed: boolean;
  hasEmbedURL: boolean;
  frameLoaded: boolean;
  streamError: string | null | undefined;
  feedCount: number;
}) {
  return (
    input.useEventEmbed &&
    input.hasEmbedURL &&
    !input.frameLoaded &&
    !input.streamError &&
    input.feedCount > 1
  );
}

export function shouldArmEmbedStartTimeout(input: {
  useEventEmbed: boolean;
  canObservePlayback: boolean;
  frameLoaded: boolean;
  feedCount: number;
  playbackStarted: boolean;
}) {
  return (
    input.useEventEmbed &&
    input.canObservePlayback &&
    input.frameLoaded &&
    input.feedCount > 1 &&
    !input.playbackStarted
  );
}
