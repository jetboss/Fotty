import type { Metadata } from "next";
import { MoreViewV2 } from "@/components/v2/MoreViewV2";

export const metadata: Metadata = {
  title: "More (preview)",
  robots: { index: false, follow: false },
};

export default function NextMorePage() {
  return <MoreViewV2 />;
}
