export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";

export const revalidate = 600;

export interface HeadlineItem {
  id: string;
  title: string;
  url: string;
  source?: string;
}

function parseGoogleNewsRss(xml: string, limit: number): HeadlineItem[] {
  const items: HeadlineItem[] = [];
  const itemBlocks = xml.match(/<item>[\s\S]*?<\/item>/gi) ?? [];

  for (const block of itemBlocks) {
    if (items.length >= limit) break;
    const titleMatch = block.match(/<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/i);
    const linkMatch = block.match(/<link>([\s\S]*?)<\/link>/i);
    const sourceMatch = block.match(/<source[^>]*>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/source>/i);
    const title = titleMatch?.[1]?.trim().replace(/&apos;/g, "'").replace(/&amp;/g, "&");
    const url = linkMatch?.[1]?.trim();
    if (!title || !url || title === "Google News") continue;
    items.push({
      id: url,
      title,
      url,
      source: sourceMatch?.[1]?.trim(),
    });
  }

  return items;
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const query = searchParams.get("q")?.trim() || "Premier League football";
  const limit = Math.min(Number(searchParams.get("limit") || "6"), 12);

  const rssUrl = `https://news.google.com/rss/search?q=${encodeURIComponent(query)}&hl=en-US&gl=US&ceid=US:en`;

  try {
    const response = await fetch(rssUrl, {
      headers: { Accept: "application/rss+xml, application/xml, text/xml" },
      next: { revalidate: 600 },
    });
    if (!response.ok) {
      throw new Error(`RSS HTTP ${response.status}`);
    }
    const xml = await response.text();
    const headlines = parseGoogleNewsRss(xml, limit);
    return NextResponse.json({ query, headlines });
  } catch (error) {
    return NextResponse.json(
      {
        query,
        headlines: [] as HeadlineItem[],
        error: error instanceof Error ? error.message : "headlines fetch failed",
      },
      { status: 502 }
    );
  }
}
