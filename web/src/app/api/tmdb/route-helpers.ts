import type { CatalogSection, MediaItem, MediaType } from "@/lib/api";

const TMDB_BASE_URL = "https://api.themoviedb.org/3";
const TMDB_IMAGE_BASE = "https://image.tmdb.org/t/p";

interface TMDBListResponse<T> {
  results?: T[];
}

interface TMDBGenre {
  name?: string;
}

export interface TMDBMediaPayload {
  id?: number;
  title?: string;
  name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  media_type?: string;
  vote_average?: number;
  release_date?: string;
  first_air_date?: string;
  runtime?: number;
  number_of_seasons?: number;
  number_of_episodes?: number;
  tagline?: string;
  status?: string;
  genres?: TMDBGenre[];
}

function imageURL(path: string | null | undefined, size: "w342" | "w500" | "w780" | "w1280" = "w500") {
  return path ? `${TMDB_IMAGE_BASE}/${size}${path}` : undefined;
}

function yearFrom(payload: TMDBMediaPayload) {
  const date = payload.release_date || payload.first_air_date;
  return date ? date.slice(0, 4) : undefined;
}

function runtimeLabel(minutes?: number) {
  if (!minutes || minutes <= 0) return undefined;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return hours > 0 ? `${hours}h ${rest}m` : `${rest}m`;
}

export function normalizeMedia(payload: TMDBMediaPayload, fallbackType: MediaType = "movie"): MediaItem | null {
  if (!payload.id) return null;

  const resolvedType = payload.media_type === "tv" || fallbackType === "tv" ? "tv" : "movie";
  const title = payload.title || payload.name;
  if (!title) return null;

  return {
    id: payload.id,
    type: resolvedType,
    title,
    overview: payload.overview || undefined,
    poster: imageURL(payload.poster_path, "w500"),
    backdrop: imageURL(payload.backdrop_path, "w1280"),
    rating: payload.vote_average,
    year: yearFrom(payload),
    meta: resolvedType === "tv" ? "TV Show" : "Movie",
    genres: payload.genres?.map((genre) => genre.name).filter(Boolean) as string[] | undefined,
    runtime: runtimeLabel(payload.runtime),
    seasons: payload.number_of_seasons,
    episodes: payload.number_of_episodes,
    tagline: payload.tagline || undefined,
    status: payload.status || undefined,
  };
}

export async function tmdbRequest<T>(path: string, query: Record<string, string> = {}): Promise<T> {
  const apiKey = process.env.TMDB_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("TMDB_API_KEY is not configured.");
  }

  const url = new URL(`${TMDB_BASE_URL}${path}`);
  url.searchParams.set("api_key", apiKey);
  url.searchParams.set("language", "en-US");

  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    next: { revalidate: 300 },
  });

  if (!response.ok) {
    throw new Error(`TMDB request failed: ${response.status}`);
  }

  return (await response.json()) as T;
}

export async function tmdbList(path: string, fallbackType: MediaType, query: Record<string, string> = {}) {
  const response = await tmdbRequest<TMDBListResponse<TMDBMediaPayload>>(path, query);
  return (response.results || [])
    .map((item) => normalizeMedia(item, fallbackType))
    .filter((item): item is MediaItem => Boolean(item));
}

export function section(id: string, title: string, subtitle: string, items: MediaItem[]): CatalogSection {
  return { id, title, subtitle, items };
}
