export const P2P_GUIDE_COPY = {
  title: "How Fotty P2P streams work",
  body: "Some Fotty streams use P2P delivery. That means stream quality may improve when more viewers are connected. If one stream is unstable, try a backup or wait a few seconds while peers connect.",
  warming: "Connecting to peers…",
  warmingHint: "P2P streams may take a few seconds to stabilize.",
} as const;

export const STREAM_GUIDE_COPY = {
  hubTitle: "Match Stream Hub",
  recommendedTitle: "Best available stream",
  noStreamsTitle: "No working stream is available yet",
  noStreamsBody: "Fotty is checking sources and will update this page when one becomes available.",
  playbackFailed: "Playback could not start from this source.",
  tryBackup: "Try backup stream",
  fottyChecking: "Fotty is checking sources",
} as const;
