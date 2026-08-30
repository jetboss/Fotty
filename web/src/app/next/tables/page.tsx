import type { Metadata } from "next";
import TablesPageClient from "@/app/tables/TablesPageClient";

export const metadata: Metadata = {
  title: "League tables (preview)",
  robots: { index: false, follow: false },
};

export default function NextTablesPage() {
  return <TablesPageClient backHref="/next" variant="v2" />;
}
