"use client";

import Link from "next/link";
import { buildV2MoreLinks } from "@/lib/v2/nav";
import { V2PageHeader, V2PageShell, v2PanelClass } from "@/components/v2/V2PageShell";
import { cn } from "@/lib/utils";

export function MoreViewV2() {
  const links = buildV2MoreLinks();
  return (
    <V2PageShell innerClassName="max-w-lg space-y-6">
      <V2PageHeader title="More" subtitle="Teams, schedule, and account tools." />

      <ul className={cn(`${v2PanelClass} divide-y divide-white/[0.06] overflow-hidden`)}>
        {links.map((item) => {
          const Icon = item.icon;
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className="flex items-center gap-4 px-4 py-4 transition hover:bg-white/[0.04]"
              >
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-white/5 text-white ring-1 ring-white/[0.06]">
                  <Icon size={18} />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-semibold text-white">{item.label}</span>
                  <span className="block text-xs text-text-tertiary">{item.subtitle}</span>
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </V2PageShell>
  );
}
