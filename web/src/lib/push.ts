"use client";

/** Show a device-local reminder. Fotty has no account-backed push server. */
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
