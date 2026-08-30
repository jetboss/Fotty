import type { NextConfig } from "next";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = dirname(fileURLToPath(import.meta.url));

const securityHeaders = [
  { key: "X-DNS-Prefetch-Control", value: "on" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), interest-cohort=()",
  },
];

const isStaticExport = process.env.IS_STATIC_EXPORT === "true";

const nextConfig: NextConfig = {
  output: isStaticExport ? "export" : "standalone",
  trailingSlash: true,
  // Playwright and curl smoke tests often hit 127.0.0.1 while Next dev serves localhost.
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  turbopack: {
    root: webRoot,
  },
  images: {
    unoptimized: isStaticExport ? true : undefined,
    remotePatterns: [
      { protocol: "https", hostname: "streamed.pk" },
      { protocol: "https", hostname: "media.api-sports.io" },
      { protocol: "https", hostname: "crests.football-data.org" },
    ],
  },
  ...(isStaticExport ? {} : {
    async headers() {
      return [
        {
          source: "/sw.js",
          headers: [
            ...securityHeaders,
            { key: "Cache-Control", value: "no-cache, no-store, must-revalidate" },
            { key: "Service-Worker-Allowed", value: "/" },
          ],
        },
        {
          source: "/api/:path*",
          headers: [
            { key: "Access-Control-Allow-Origin", value: "*" },
            { key: "Access-Control-Allow-Methods", value: "GET,POST,OPTIONS,DELETE" },
            { key: "Access-Control-Allow-Headers", value: "Content-Type,Authorization,X-Fotty-Email,X-Fotty-User-Id,X-Fotty-P2P-Cid,Accept" },
          ],
        },
        {
          source: "/:path*",
          headers: securityHeaders,
        },
      ];
    },
    async redirects() {
      return [{ source: "/media/:type/:id", destination: "/search", permanent: false }];
    },
  }),
};

export default nextConfig;
