import type { MetadataRoute } from "next";
import { getSiteUrl } from "@/lib/fotty-config";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  const base = getSiteUrl();

  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: ["/mvp", "/mvp/", "/admin", "/admin/", "/api/", "/watch/"],
    },
    sitemap: `${base}/sitemap.xml`,
  };
}
