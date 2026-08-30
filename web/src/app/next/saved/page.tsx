import type { Metadata } from "next";
import { SavedViewV2 } from "@/components/v2/SavedViewV2";

export const metadata: Metadata = {
  title: "Saved (preview)",
  robots: { index: false, follow: false },
};

export default function NextSavedPage() {
  return <SavedViewV2 />;
}
