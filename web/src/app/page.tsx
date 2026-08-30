import type { Metadata } from "next";
import { getMatchFeed } from "@/lib/server/match-feed";
import { HomeViewV2 } from "@/components/v2/HomeViewV2";

export const revalidate = 45;

export const metadata: Metadata = {
  title: "FOTTY | Live Sports, Match Day, and Channels",
  description: "Browse live sports, follow match day fixtures, and install Fotty for a fast app-like viewing experience.",
};

export default async function Home() {
  const initialMatches = await getMatchFeed().catch(() => []);

  return (
    <>
      <section className="sr-only">
        <h1>Fotty Home</h1>
      </section>
      <HomeViewV2 initialMatches={initialMatches} />
    </>
  );
}
