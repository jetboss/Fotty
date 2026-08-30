export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { normalizeMedia, tmdbRequest } from "../route-helpers";

interface SearchResponse {
  results?: Array<{
    media_type?: string;
    id?: number;
    title?: string;
    name?: string;
    overview?: string;
    poster_path?: string | null;
    backdrop_path?: string | null;
    vote_average?: number;
    release_date?: string;
    first_air_date?: string;
  }>;
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const query = searchParams.get("q")?.trim();

  if (!query) {
    return NextResponse.json([]);
  }

  try {
    const response = await tmdbRequest<SearchResponse>("/search/multi", {
      query,
      include_adult: "false",
      page: "1",
    });

    const results = (response.results || [])
      .filter((item) => item.media_type === "movie" || item.media_type === "tv")
      .map((item) => normalizeMedia(item, item.media_type === "tv" ? "tv" : "movie"))
      .filter(Boolean);

    return NextResponse.json(results);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 502 });
  }
}
