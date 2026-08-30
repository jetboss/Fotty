export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import type { MediaType } from "@/lib/api";
import { normalizeMedia, tmdbRequest, type TMDBMediaPayload } from "../route-helpers";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const type = searchParams.get("type") as MediaType | null;
  const id = searchParams.get("id");

  if ((type !== "movie" && type !== "tv") || !id) {
    return NextResponse.json({ error: "Missing media type or id" }, { status: 400 });
  }

  try {
    const detail = await tmdbRequest<TMDBMediaPayload>(`/${type}/${id}`, {
      append_to_response: "credits",
    });
    const item = normalizeMedia(detail, type);

    if (!item) {
      return NextResponse.json({ error: "Media not found" }, { status: 404 });
    }

    return NextResponse.json(item);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 502 });
  }
}
