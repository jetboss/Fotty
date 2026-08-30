export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import type { ScrapedMatch } from "@/lib/api";
import { getP2PApiPassword } from "@/lib/server-env";

export const revalidate = 45;

const SCRAPER_BASE = (process.env.SCRAPER_BASE || "").replace(/\/$/, "");

interface ChannelPayload {
  id?: string;
  cid?: string;
  title?: string;
  name?: string;
  availability?: number;
  categories?: string[];
  bitrate_kbps?: number;
}

const REGION_NAMES: Record<string, string> = {
  AR: "Argentina",
  AU: "Australia",
  BE: "Belgium",
  BR: "Brazil",
  CA: "Canada",
  DE: "Germany",
  ES: "Spain",
  EU: "Europe",
  FR: "France",
  IT: "Italy",
  NL: "Netherlands",
  PL: "Poland",
  PT: "Portugal",
  RU: "Russia",
  TR: "Turkiye",
  UK: "United Kingdom",
  US: "United States",
};

const KNOWN_ACRONYMS = new Set(["AFL", "BT", "ESPN", "F1", "FOX", "HD", "MLB", "NBA", "NFL", "NHL", "SKY", "TNT", "UFC", "UK", "USA"]);

async function fetchChannels() {
  const apiPassword = getP2PApiPassword();
  if (!apiPassword || !SCRAPER_BASE) return [];

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6500);

  try {
    const response = await fetch(`${SCRAPER_BASE}/matches`, {
      headers: {
        Authorization: `Bearer ${apiPassword}`,
        Accept: "application/json",
      },
      signal: controller.signal,
      next: { revalidate: 45 },
    });

    if (!response.ok) return [];
    const payload = await response.json();
    return Array.isArray(payload) ? (payload as ChannelPayload[]) : [];
  } catch {
    return [];
  } finally {
    clearTimeout(timeout);
  }
}

function titleCase(value: string) {
  return value
    .split(/(\s+|-|\+)/)
    .map((part) => {
      const normalized = part.toUpperCase();
      if (KNOWN_ACRONYMS.has(normalized) || /^\d+$/.test(part) || /^\W+$/.test(part)) return part;
      return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
    })
    .join("");
}

function cleanChannelTitle(rawTitle: string) {
  let title = rawTitle
    .replace(/\s+/g, " ")
    .replace(/\s*\((?:backup|alt|acestream|hd)\)\s*/gi, " ")
    .trim();

  const bracketRegion = title.match(/\[([A-Z]{2,3})\]\s*$/i)?.[1]?.toUpperCase();
  title = title.replace(/\s*\[[^\]]+\]\s*$/g, "").trim();

  const prefixRegion = title.match(/^([A-Z]{2,3}):\s*/i)?.[1]?.toUpperCase();
  title = title.replace(/^[A-Z]{2,3}:\s*/i, "").trim();

  if (/^[A-Z0-9+\-\s.]+$/.test(title)) {
    title = titleCase(title);
  }

  title = title
    .replace(/\bBt\b/g, "BT")
    .replace(/\bDazn\b/g, "DAZN")
    .replace(/\bEspn\b/g, "ESPN")
    .replace(/\bHd\b/g, "HD")
    .replace(/\b4k\b/gi, "4K")
    .replace(/\bRtl\b/g, "RTL")
    .replace(/\bTv\b/g, "TV")
    .trim();

  const regionCode = bracketRegion || prefixRegion;
  return {
    title: title || rawTitle,
    region: regionCode ? REGION_NAMES[regionCode] || regionCode : undefined,
  };
}

function inferSport(rawTitle: string, categories: string[] = []) {
  const text = `${rawTitle} ${categories.join(" ")}`.toLowerCase();
  if (/(snooker|billiards|pool)/.test(text)) return "Snooker";
  if (/(cricket|willow)/.test(text)) return "Cricket";
  if (/(f1|formula|motorsport|racing|moto gp|motogp|rally)/.test(text)) return "Motorsport";
  if (/(ufc|mma|fight|boxing|wwe)/.test(text)) return "Combat Sports";
  if (/(basket|nba|euroleague)/.test(text)) return "Basketball";
  if (/(hockey|nhl)/.test(text)) return "Hockey";
  if (/(football|soccer|premier|laliga|serie a|bundesliga|champions league|uefa|sport)/.test(text)) return "Football";
  return "Live Sports";
}

function streamQuality(bitrate?: number): ScrapedMatch["quality"] {
  if (!bitrate) return "Unknown";
  if (bitrate >= 850) return "HD";
  if (bitrate >= 500) return "HQ";
  return "SD";
}

function rankChannel(channel: ScrapedMatch) {
  const availabilityScore = Math.round((channel.availability || 0) * 1000);
  const bitrateScore = Math.min(channel.bitrate_kbps || 0, 1600);
  const qualityScore = channel.quality === "HD" ? 250 : channel.quality === "HQ" ? 125 : 0;
  return availabilityScore + bitrateScore + qualityScore;
}

function mapChannel(channel: ChannelPayload): ScrapedMatch | null {
  const cid = channel.cid || channel.id;
  const rawTitle = channel.title || channel.name;
  if (!cid || !rawTitle) return null;

  const cleaned = cleanChannelTitle(rawTitle);
  const categories = channel.categories || [];
  const quality = streamQuality(channel.bitrate_kbps);
  const sport = inferSport(rawTitle, categories);
  const subtitle = [
    sport,
    cleaned.region,
    quality !== "Unknown" ? quality : undefined,
    "P2P",
  ].filter(Boolean).join(" · ");

  const match: ScrapedMatch = {
    id: cid,
    cid,
    title: rawTitle,
    displayTitle: cleaned.title,
    subtitle,
    kind: "channel",
    availability: Number(channel.availability || 0),
    categories,
    bitrate_kbps: channel.bitrate_kbps,
    league: "P2P Channels",
    sport,
    region: cleaned.region,
    network: cleaned.title,
    quality,
    status: channel.availability && channel.availability > 0 ? "P2P Ready" : "Warming",
    coverage: "channel",
    playbackType: "p2p",
  };

  return { ...match, rank: rankChannel(match) };
}

function dedupeChannels(channels: ScrapedMatch[]) {
  const byTitle = new Map<string, ScrapedMatch & { alternateCount: number }>();

  for (const channel of channels) {
    const key = `${channel.displayTitle || channel.title}:${channel.region || ""}`.toLowerCase();
    const existing = byTitle.get(key);
    if (!existing) {
      byTitle.set(key, { ...channel, alternateCount: 1 });
      continue;
    }

    existing.alternateCount += 1;
    if ((channel.rank || 0) > (existing.rank || 0)) {
      byTitle.set(key, { ...channel, alternateCount: existing.alternateCount });
    }
  }

  return Array.from(byTitle.values()).sort((a, b) => (b.rank || 0) - (a.rank || 0));
}

async function getP2PChannelFeed(): Promise<ScrapedMatch[]> {
  if (process.env.IS_STATIC_EXPORT === "true") {
    return [];
  }

  const channels = (await fetchChannels())
    .map(mapChannel)
    .filter((channel): channel is ScrapedMatch => Boolean(channel));

  return dedupeChannels(channels);
}

export async function GET() {
  return NextResponse.json(await getP2PChannelFeed());
}
