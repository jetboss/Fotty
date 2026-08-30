/** True when Fotty is running as an installed PWA (Home Screen). */
export function isStandaloneDisplayMode() {
  if (typeof window === "undefined") return false;
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    window.matchMedia("(display-mode: fullscreen)").matches ||
    // Legacy iOS Safari
    ("standalone" in window.navigator && Boolean((window.navigator as Navigator & { standalone?: boolean }).standalone))
  );
}

export function isIosDevice() {
  if (typeof navigator === "undefined") return false;
  return /iPhone|iPad|iPod/i.test(navigator.userAgent);
}

export function isIosSafari() {
  if (!isIosDevice()) return false;
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  return /Safari/i.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS/i.test(ua);
}

export function canShowAddToHomeScreenHint() {
  return isIosDevice() && !isStandaloneDisplayMode();
}

const PWA_DISMISS_KEY = "fotty.pwa.install.dismissed.v1";

export function isPwaInstallDismissed() {
  if (typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(PWA_DISMISS_KEY) === "1";
  } catch {
    return false;
  }
}

export function dismissPwaInstallHint() {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PWA_DISMISS_KEY, "1");
  } catch {
    // ignore
  }
}
