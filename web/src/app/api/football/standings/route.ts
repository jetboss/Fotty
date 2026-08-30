export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { fetchLeagueFootballData } from "@/lib/server/football-data";
import type { FootballLeagueTab } from "@/lib/football-leagues";

/** 6h — standings change on match days, not minute-by-minute */
export const revalidate = 21_600;

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const league = (searchParams.get("league") || "premierLeague") as FootballLeagueTab;
  const includeScorers = searchParams.get("scorers") === "1";
  const payload = await fetchLeagueFootballData(league, includeScorers);

  if ("error" in payload && payload.error) {
    return NextResponse.json(payload, { status: 502 });
  }

  return NextResponse.json(payload);
}
