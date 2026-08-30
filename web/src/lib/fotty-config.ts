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
} as const;

export function getSiteUrl() {
  return (process.env.NEXT_PUBLIC_SITE_URL || FOTTY_DEFAULTS.siteUrl).replace(/\/$/, "");
}
