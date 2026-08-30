/**
 * Hosts allowlisted in next.config.ts `images.remotePatterns`.
 * Anything else (or SVGs, which the optimizer rejects) renders unoptimized
 * so an unknown provider URL never crashes the image loader.
 */
const OPTIMIZED_IMAGE_HOSTS = new Set([
  "streamed.pk",
  "media.api-sports.io",
  "crests.football-data.org",
]);

export function isOptimizedImageSrc(src: string | undefined): boolean {
  if (!src) return false;
  if (src.startsWith("/")) return true;
  try {
    const url = new URL(src);
    if (url.pathname.toLowerCase().endsWith(".svg")) return false;
    return OPTIMIZED_IMAGE_HOSTS.has(url.hostname);
  } catch {
    return false;
  }
}
