import type { ScrapedMatch } from "@/lib/api";
import { GET as getMatchesResponse } from "@/app/api/matches/route";

async function readMatchResponse(response: Response): Promise<ScrapedMatch[]> {
  const payload = (await response.json().catch(() => [])) as unknown;
  return Array.isArray(payload) ? (payload as ScrapedMatch[]) : [];
}

export async function getMatchFeed(): Promise<ScrapedMatch[]> {
  return readMatchResponse(await getMatchesResponse());
}

/** P2P channel catalog retired with the homelab. */
export async function getP2PChannelFeed(): Promise<ScrapedMatch[]> {
  return [];
}
