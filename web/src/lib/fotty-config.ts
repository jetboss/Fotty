/**
 * Canonical Fotty web service defaults.
 * Match catalog for getfotty.com comes from StreamEx (same Nexus feed as iOS),
 * not from retired homelab scraper/P2P hosts.
 */

export const FOTTY_DEFAULTS = {
  siteUrl: "https://getfotty.com",
  legalBaseUrl: "https://getfotty.com",
  /** Cloudflare Worker for Watch playback APIs on static FTP (no Node `/api` on Apache). */
  playbackApiBase: "https://fotty-playback-v3.adaptive-rhubarb.workers.dev",
  /** Empty until a replacement auth host exists (homelab PocketBase retired). */
  pocketBaseUrl: "",
  /** Empty until a replacement P2P broker exists. */
  p2pApiBase: "",
  scraperBase: "",
} as const;

export function getSiteUrl() {
  return (process.env.NEXT_PUBLIC_SITE_URL || FOTTY_DEFAULTS.siteUrl).replace(/\/$/, "");
}

export function getPocketBaseUrl() {
  return (
    process.env.POCKETBASE_BASE_URL ||
    process.env.NEXT_PUBLIC_POCKETBASE_URL ||
    FOTTY_DEFAULTS.pocketBaseUrl
  ).replace(/\/$/, "");
}

export function getP2PApiBase() {
  const internal = process.env.P2P_API_INTERNAL_BASE?.trim();
  const external = process.env.P2P_API_BASE || FOTTY_DEFAULTS.p2pApiBase;
  return (internal || external).replace(/\/$/, "");
}

/** Public broker origin (for browser-direct segment URLs in HLS manifests). */
export function getPublicP2POrigin() {
  const base =
    process.env.NEXT_PUBLIC_P2P_API_BASE ||
    process.env.P2P_API_BASE ||
    FOTTY_DEFAULTS.p2pApiBase;
  if (!base) return "";
  return new URL(base.endsWith("/") ? base : `${base}/`).origin;
}

export function getScraperBase() {
  return (process.env.SCRAPER_BASE || FOTTY_DEFAULTS.scraperBase).replace(/\/$/, "");
}
