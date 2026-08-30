import { trackEvent, type FottyEventName, type FottyEventPayload } from "@/lib/analytics";

export type StreamDiagnosticEvent =
  | "stream_guide_view"
  | "stream_selected"
  | "stream_switch"
  | "playback_start_success"
  | "playback_start_failure"
  | "manifest_load_failure"
  | "playback_stalled"
  | "playback_recovered"
  | "fallback_suggested"
  | "fallback_used"
  | "stream_marked_offline"
  | "stream_health_refresh";

export interface StreamDiagnosticPayload extends FottyEventPayload {
  matchId?: string;
  sourceId?: string;
  streamType?: string;
  providerType?: string;
  healthState?: string;
  healthScore?: number;
  reason?: string;
  playbackMode?: "event" | "p2p";
}

const EVENT_MAP: Partial<Record<StreamDiagnosticEvent, FottyEventName>> = {
  playback_start_failure: "playback_error",
  playback_stalled: "playback_stalled",
  playback_recovered: "playback_recovered",
  stream_switch: "change_source_click",
};

export function logStreamDiagnostic(event: StreamDiagnosticEvent, payload: StreamDiagnosticPayload = {}) {
  const mapped = EVENT_MAP[event];
  if (mapped) {
    trackEvent(mapped, {
      ...payload,
      diagnostic: event,
    });
    return;
  }

  if (process.env.NODE_ENV !== "production") {
    console.info("[Fotty stream diagnostic]", event, payload);
  }

  trackEvent("change_source_click", {
    ...payload,
    diagnostic: event,
  });
}
