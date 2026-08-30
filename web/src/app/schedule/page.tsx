import type { Metadata } from "next";
import { getMatchFeed } from "@/lib/server/match-feed";
import { ScheduleViewV2 } from "@/components/v2/ScheduleViewV2";
import { isV2Enabled } from "@/lib/v2/preview";
import { redirect } from "next/navigation";

export const revalidate = 45;

export const metadata: Metadata = {
  title: "Schedule",
  description: "Browse upcoming fixtures by day on Fotty.",
  alternates: { canonical: "/schedule" },
};

export default async function SchedulePage() {
  if (!isV2Enabled()) {
    redirect("/");
  }

  const initialMatches = await getMatchFeed().catch(() => []);
  return <ScheduleViewV2 initialMatches={initialMatches} />;
}
