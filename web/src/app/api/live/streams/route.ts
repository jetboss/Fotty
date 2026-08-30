export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";

const DESKTOP_SAFARI_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";

const STREAM_PROVIDERS = [
  {
    label: "StreameX",
    baseURL: "https://www.streamex.net",
    pathPrefix: "/api/live/stream",
  },
  {
    label: "StreameX Mirror",
    baseURL: "https://streamex.sh",
    pathPrefix: "/api/live/stream",
  },
  {
    label: "Streamed Backup",
    baseURL: "https://streamed.pk",
    pathPrefix: "/api/stream",
  },
];

/** Prefer StreamEx `admin` (PPV), `delta`, and `golf` on web. */
const SOURCE_PRIORITY = ["admin", "delta", "golf", "hotel", "echo", "india", "alpha"];

interface ProviderVariant {
  id?: string;
  streamNo?: number;
  language?: string;
  hd?: boolean;
  embedUrl?: string;
  source?: string;
  viewers?: number;
  heatTier?: string;
}

async function fetchVariants(provider: (typeof STREAM_PROVIDERS)[number], source: string, id: string) {
  const sourcePart = encodeURIComponent(source);
  const idPart = encodeURIComponent(id);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6500);

  try {
    const response = await fetch(`${provider.baseURL}${provider.pathPrefix}/${sourcePart}/${idPart}`, {
      headers: {
        Accept: "application/json",
        Referer: provider.baseURL,
        "User-Agent": DESKTOP_SAFARI_USER_AGENT,
      },
      signal: controller.signal,
      cache: "no-store",
    });

    if (!response.ok) return [];
    const payload = await response.json();
    const variants = Array.isArray(payload)
      ? payload
      : payload?.streams || payload?.variants || payload?.data || payload?.result || [];

    return (Array.isArray(variants) ? variants : []).map((variant: ProviderVariant) => ({
      id: variant.id || id,
      source: variant.source || source,
      streamNo: variant.streamNo || 1,
      language: variant.language || "",
      hd: variant.hd === true,
      embedUrl: variant.embedUrl,
      viewers: Number(variant.viewers || 0),
      heatTier: variant.heatTier,
      provider: provider.label,
    }));
  } catch {
    return [];
  } finally {
    clearTimeout(timeout);
  }
}

function heatTierRank(value?: string) {
  switch (value?.toLowerCase()) {
    case "veryhigh":
      return 0;
    case "high":
      return 1;
    case "medium":
      return 2;
    case "low":
      return 3;
    default:
      return 4;
  }
}

function sourceRank(source?: string) {
  const index = SOURCE_PRIORITY.indexOf(source?.toLowerCase() || "");
  return index >= 0 ? index : 999;
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const source = searchParams.get("source")?.trim();
  const id = searchParams.get("id")?.trim();

  if (!source || !id) {
    return NextResponse.json({ error: "Missing source or id" }, { status: 400 });
  }

  const providerResults = await Promise.all(
    STREAM_PROVIDERS.map((provider) => fetchVariants(provider, source, id))
  );
  const variants = providerResults
    .flat()
    .filter((variant) => variant.embedUrl)
    .filter((variant, index, all) => all.findIndex((item) => item.embedUrl === variant.embedUrl) === index)
    .sort((a, b) => {
      const sourceDelta = sourceRank(a.source) - sourceRank(b.source);
      if (sourceDelta !== 0) return sourceDelta;

      const heatDelta = heatTierRank(a.heatTier) - heatTierRank(b.heatTier);
      if (heatDelta !== 0) return heatDelta;

      if (a.hd !== b.hd) return Number(b.hd) - Number(a.hd);
      if (a.viewers !== b.viewers) return b.viewers - a.viewers;
      return a.streamNo - b.streamNo;
    });

  if (variants.length === 0) {
    variants.push({
      id,
      source,
      streamNo: 1,
      language: "",
      hd: true,
      embedUrl: `https://embedsports.top/embed/${encodeURIComponent(source)}/${encodeURIComponent(id)}/1`,
      viewers: 0,
      heatTier: "legacy",
      provider: "Legacy",
    });
  }

  return NextResponse.json(variants, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
    },
  });
}
