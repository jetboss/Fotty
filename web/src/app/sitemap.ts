import type { MetadataRoute } from "next";
import { getSiteUrl } from "@/lib/fotty-config";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const base = getSiteUrl();
  const routes = [
    "",
    "/search",
    "/schedule",
    "/tables",
    "/teams",
    "/favorites",
    "/welcome",
    "/help",
    "/support",
    "/subscribe",
    "/login",
    "/privacy",
    "/terms",
  ];

  // App-first companion: Home / Discover / Schedule. Guide + Swarm (P2P) retired.
  const hourly = new Set(["", "/search", "/schedule"]);
  const highPriority = new Set(["/search", "/schedule", "/tables"]);

  return routes.map((path) => ({
    url: `${base}${path}`,
    lastModified: new Date(),
    changeFrequency: hourly.has(path) ? "hourly" : "weekly",
    priority: path === "" ? 1 : highPriority.has(path) ? 0.9 : 0.6,
  }));
}
