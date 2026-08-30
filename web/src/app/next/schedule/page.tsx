import type { Metadata } from "next";
import { getMatchFeed } from "@/lib/server/match-feed";
import { ScheduleViewV2 } from "@/components/v2/ScheduleViewV2";

export const revalidate = 45;

export const metadata: Metadata = {
  title: "Schedule (preview)",
  description: "Fixture calendar preview for the next-gen Fotty shell.",
  robots: { index: false, follow: false },
};

export default async function NextSchedulePage() {
  const initialMatches = await getMatchFeed().catch(() => []);
  return <ScheduleViewV2 initialMatches={initialMatches} />;
}
