"use client";

type AnalyticsValue = string | number | boolean | null | undefined;

export type FottyEventName =
  | "support_monthly_click"
  | "support_tip_click"
  | "partner_inquiry_click"
  | "collab_inquiry_saved"
  | "support_pledge_saved"
  | "watch_match_click"
  | "change_source_click"
  | "track_team_click"
  | "browser_notifications_permission"
  | "sponsor_slot_click"
  | "subscription_plan_select"
  | "subscription_checkout_click"
  | "subscription_checkout_success"
  | "subscription_local_activation"
  | "whatsapp_pay_click"
  | "web_push_subscribe"
  | "login_attempt"
  | "signup_attempt"
  | "runtime_error"
  | "playback_error"
  | "playback_stalled"
  | "playback_recovered"
  | "stream_token_failed"
  | "matches_api_failed";

export type FottyEventPayload = Record<string, AnalyticsValue>;

const EVENT_KEY = "fotty.web.events.v1";
const MAX_EVENTS = 80;

interface StoredEvent {
  name: FottyEventName;
  payload: FottyEventPayload;
  at: string;
  path: string;
}

function readEvents(): StoredEvent[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(EVENT_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function sendPlausibleEvent(name: FottyEventName, payload: FottyEventPayload) {
  if (typeof window === "undefined" || typeof window.plausible !== "function") return;

  const props = Object.fromEntries(
    Object.entries(payload).flatMap(([key, value]) => {
      if (value === undefined || value === null) return [];
      return [[key, typeof value === "boolean" ? String(value) : value] as const];
    })
  );

  window.plausible(name, Object.keys(props).length > 0 ? { props } : undefined);
}

export function trackEvent(name: FottyEventName, payload: FottyEventPayload = {}) {
  if (typeof window === "undefined") return;

  const event: StoredEvent = {
    name,
    payload,
    at: new Date().toISOString(),
    path: window.location.pathname,
  };

  try {
    window.localStorage.setItem(EVENT_KEY, JSON.stringify([event, ...readEvents()].slice(0, MAX_EVENTS)));
  } catch {
    // Analytics should never block match-day flows.
  }

  sendPlausibleEvent(name, payload);

  if (process.env.NODE_ENV !== "production") {
    console.info("[Fotty event]", event);
  }
}
