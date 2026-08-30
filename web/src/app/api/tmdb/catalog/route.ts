export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { section, tmdbList } from "../route-helpers";

export async function GET() {
  try {
    const [trending, popularMovies, topRatedMovies, airingToday, popularTV, nowPlaying] = await Promise.all([
      tmdbList("/trending/all/week", "movie"),
      tmdbList("/movie/popular", "movie"),
      tmdbList("/movie/top_rated", "movie"),
      tmdbList("/tv/airing_today", "tv"),
      tmdbList("/tv/popular", "tv"),
      tmdbList("/movie/now_playing", "movie"),
    ]);

    const filteredTrending = trending.filter((item) => item.type === "movie" || item.type === "tv");
    const hero = filteredTrending.find((item) => item.backdrop) || filteredTrending[0] || nowPlaying[0];

    return NextResponse.json({
      hero,
      sections: [
        section("trending", "Trending This Week", "What everyone's watching", filteredTrending),
        section("popular-movies", "Popular Movies", "Most watched right now", popularMovies),
        section("airing-today", "Airing Today", "New episodes dropping", airingToday),
        section("popular-tv", "Popular TV Shows", "Binge-worthy picks", popularTV),
        section("top-rated", "Top Rated", "All-time favorites", topRatedMovies),
        section("now-playing", "Now Playing", "Fresh from theaters", nowPlaying),
      ].filter((item) => item.items.length > 0),
    });
  } catch (error) {
    return NextResponse.json({ error: String(error), sections: [] }, { status: 502 });
  }
}
