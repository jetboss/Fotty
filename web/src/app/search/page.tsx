import type { Metadata } from "next";
import { getMatchFeed } from "@/lib/server/match-feed";
import { dedupeMatches } from "@/lib/v2/search";
import { DiscoverViewV2 } from "@/components/v2/DiscoverViewV2";

export const revalidate = 45;

export const metadata: Metadata = {
  title: "Discover | Fotty",
  description: "Search and browse live fixtures — find something to watch on Fotty.",
};

export default async function SearchPage() {
  const matches = await getMatchFeed().catch(() => []);
  const initialIndex = dedupeMatches(matches.filter((match) => match.kind === "fixture" || !match.kind));

  return (
    <>
      <section className="sr-only">
        <h1>Discover</h1>
      </section>
      <DiscoverViewV2 initialIndex={initialIndex} />
    </>
  );
}
