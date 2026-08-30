export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { fetchFootballDataMatches } from "@/lib/server/football-data";


export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const payload = await fetchFootballDataMatches({
    dateFrom: searchParams.get("dateFrom") || undefined,
    dateTo: searchParams.get("dateTo") || undefined,
    status: searchParams.get("status") || undefined,
    limit: searchParams.get("limit") || undefined,
    competition: searchParams.get("competition") || undefined,
    season: searchParams.get("season") || undefined,
  });

  if (!payload.configured) {
    return NextResponse.json(payload, { status: 503 });
  }
  if ("error" in payload && payload.error && payload.matches.length === 0) {
    return NextResponse.json(payload, { status: 502 });
  }

  return NextResponse.json(payload);
}
