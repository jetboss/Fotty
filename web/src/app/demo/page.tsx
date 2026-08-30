import type { Metadata } from "next";
import { DemoLanding } from "./DemoLanding";

export const metadata: Metadata = {
  title: "Fotty — Match-Day Command Center",
  description:
    "Live football, matchday clarity, and stable match access. Fotty brings fixtures, match hubs, highlights, Arena, and Insights into one premium sports experience.",
  openGraph: {
    title: "Fotty — Match-Day Command Center",
    description:
      "Live football, matchday clarity, and stable match access. A premium sports experience built for fans who care.",
    type: "website",
  },
};

export default function DemoPage() {
  return <DemoLanding />;
}
