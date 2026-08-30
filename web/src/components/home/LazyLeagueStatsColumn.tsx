"use client";

import dynamic from "next/dynamic";
import type { ComponentProps } from "react";
const LeagueStatsColumn = dynamic(
  () => import("@/components/home/LeagueStatsColumn").then((mod) => mod.LeagueStatsColumn),
  {
    ssr: false,
    loading: () => <LeagueStatsSkeleton />,
  }
);

type Props = ComponentProps<typeof LeagueStatsColumn>;

export function LazyLeagueStatsColumn(props: Props) {
  return <LeagueStatsColumn {...props} />;
}

function LeagueStatsSkeleton() {
  return (
    <div className="space-y-4">
      <div className="h-48 animate-pulse rounded-xl bg-white/5" />
      <div className="h-36 animate-pulse rounded-xl bg-white/5" />
    </div>
  );
}
