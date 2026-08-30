import type { Metadata } from "next";
import { SettingsViewV2 } from "@/components/v2/SettingsViewV2";

export const metadata: Metadata = {
  title: "Settings (preview)",
  robots: { index: false, follow: false },
};

export default function NextSettingsPage() {
  return <SettingsViewV2 />;
}
