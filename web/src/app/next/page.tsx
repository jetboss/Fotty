import type { Metadata } from "next";
import { getMatchFeed } from "@/lib/server/match-feed";
import { HomeViewV2 } from "@/components/v2/HomeViewV2";

export const revalidate = 45;

export const metadata: Metadata = {
  title: "Home (preview)",
  description: "Fotty next-gen home — watch-first layout with neutral shell. Local preview only.",
  robots: { index: false, follow: false },
};

export default async function NextHomePage() {
  const initialMatches = await getMatchFeed().catch(() => []);

  return (
    <>
      <section className="sr-only">
        <h1>Fotty home preview</h1>
      </section>
      <HomeViewV2 initialMatches={initialMatches} />
    </>
  );
}
