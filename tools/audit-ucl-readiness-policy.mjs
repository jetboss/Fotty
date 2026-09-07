export const supportedUCLSourceCodes = Object.freeze([
  "admin",
  "delta",
  "echo",
  "golf",
  "hotel",
  "india",
  "alpha",
]);

export function usableWorkerVariantCount(payload) {
  const variants = Array.isArray(payload)
    ? payload
    : payload?.streams || payload?.variants || payload?.data || payload?.result || [];
  if (!Array.isArray(variants)) return 0;

  return variants.filter((variant) => {
    if (!variant || typeof variant !== "object") return false;
    const provider = String(variant.provider || "").trim().toLowerCase();
    const heatTier = String(variant.heatTier || "").trim().toLowerCase();
    if (provider === "legacy" || heatTier === "legacy") return false;
    try {
      return new URL(String(variant.embedUrl || "").trim()).protocol === "https:";
    } catch {
      return false;
    }
  }).length;
}
