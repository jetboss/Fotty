import type { Metadata } from "next";
import { MoreViewV2 } from "@/components/v2/MoreViewV2";
import { isV2Enabled } from "@/lib/v2/preview";
import { redirect } from "next/navigation";

export const metadata: Metadata = {
  title: "More",
  description: "Teams, schedule, tables, and account tools on Fotty.",
  robots: { index: false, follow: true },
};

export default function MorePage() {
  if (!isV2Enabled()) {
    redirect("/settings");
  }

  return <MoreViewV2 />;
}
