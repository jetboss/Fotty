import type { Metadata } from "next";
import TablesPageClient from "./TablesPageClient";
import { isV2Enabled, v2HomePath } from "@/lib/v2/preview";

export const metadata: Metadata = {
  title: "League Tables",
  description:
    "Live standings and top scorers for the Premier League, Champions League, La Liga, Serie A, Bundesliga, and Ligue 1.",
  alternates: { canonical: "/tables" },
};

export default function TablesPage() {
  const v2 = isV2Enabled();
  return <TablesPageClient backHref={v2 ? v2HomePath() : undefined} variant={v2 ? "v2" : "classic"} />;
}
