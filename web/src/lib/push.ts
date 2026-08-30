"use client";

const LOCAL_PUSH_KEY = "fotty.web.pushSubscription.v1";

function urlBase64ToUint8Array(base64String: string) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = window.atob(base64);
  const output = new Uint8Array(raw.length);
  for (let index = 0; index < raw.length; index += 1) {
    output[index] = raw.charCodeAt(index);
  }
  return output;
}

export function isWebPushSupported() {
  return typeof window !== "undefined" && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
}

export function readLocalPushSubscription(): PushSubscriptionJSON | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(LOCAL_PUSH_KEY);
    return raw ? (JSON.parse(raw) as PushSubscriptionJSON) : null;
  } catch {
    return null;
  }
}

export function saveLocalPushSubscription(subscription: PushSubscription) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(LOCAL_PUSH_KEY, JSON.stringify(subscription.toJSON()));
  } catch {
    // Ignore storage errors.
  }
}

export async function subscribeToWebPush(vapidPublicKey?: string) {
  if (!isWebPushSupported()) {
    return { ok: false as const, reason: "unsupported" };
  }

  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    return { ok: false as const, reason: permission };
  }

  const registration = await navigator.serviceWorker.ready;
  let subscription = await registration.pushManager.getSubscription();

  if (!subscription && vapidPublicKey) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
    });
  }

  if (!subscription) {
    return { ok: false as const, reason: "no_subscription" };
  }

  saveLocalPushSubscription(subscription);
  return { ok: true as const, subscription };
}

export async function syncPushSubscription(subscription: PushSubscription, token?: string) {
  if (!token) return { ok: false as const };

  const response = await fetch("/api/push/subscribe", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: token,
    },
    body: JSON.stringify({
      endpoint: subscription.endpoint,
      subscription: subscription.toJSON(),
    }),
  });

  return { ok: response.ok, payload: await response.json().catch(() => ({})) };
}

export async function showMatchReminderNotification(input: {
  title: string;
  body: string;
  url: string;
  tag: string;
}) {
  if (!("Notification" in window) || Notification.permission !== "granted") {
    return false;
  }

  try {
    const registration = await navigator.serviceWorker.ready;
    await registration.showNotification(input.title, {
      body: input.body,
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      tag: input.tag,
      data: { url: input.url },
    });
    return true;
  } catch {
    try {
      const notification = new Notification(input.title, {
        body: input.body,
        icon: "/icon-192.png",
        tag: input.tag,
      });
      notification.onclick = () => {
        window.focus();
        window.location.href = input.url;
        notification.close();
      };
      return true;
    } catch {
      return false;
    }
  }
}
