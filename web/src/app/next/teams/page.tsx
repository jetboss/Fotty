import type { Metadata } from "next";
import { TeamsManager } from "@/components/TeamsManager";

export const metadata: Metadata = {
  title: "Teams (preview)",
  description: "Track teams for personalized home rails — Fotty v2 preview.",
  robots: { index: false, follow: false },
};

export default function NextTeamsPage() {
  return (
    <>
      <section className="sr-only">
        <h1>Teams preview</h1>
      </section>
      <TeamsManager variant="v2" backHref="/next" homeHref="/next" />
    </>
  );
}
