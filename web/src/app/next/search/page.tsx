import { getMatchFeed } from "@/lib/server/match-feed";
import { dedupeMatches } from "@/lib/v2/search";
import { DiscoverViewV2 } from "@/components/v2/DiscoverViewV2";

export const revalidate = 45;

export default async function NextSearchPage() {
  const matches = await getMatchFeed().catch(() => []);
  const initialIndex = dedupeMatches(matches.filter((match) => match.kind === "fixture" || !match.kind));
  return <DiscoverViewV2 initialIndex={initialIndex} />;
}
