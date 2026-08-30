import type { ScrapedMatch } from "@/lib/api";
import { MatchScoreboardCard } from "./MatchScoreboardCard";

interface ArenaCardProps {
  match: ScrapedMatch;
  returnTo?: string;
}

export function HomeArenaCard({ match, returnTo = "/" }: ArenaCardProps) {
  return <MatchScoreboardCard match={match} returnTo={returnTo} layout="rail" />;
}
