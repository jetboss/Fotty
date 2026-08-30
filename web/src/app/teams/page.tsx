"use client";

import { TeamsManager } from "@/components/TeamsManager";
import { isV2Enabled, v2HomePath } from "@/lib/v2/preview";

export default function TeamsPage() {
  const v2 = isV2Enabled();
  return (
    <TeamsManager
      variant={v2 ? "v2" : "classic"}
      backHref={v2 ? v2HomePath() : undefined}
      homeHref={v2 ? v2HomePath() : undefined}
    />
  );
}
