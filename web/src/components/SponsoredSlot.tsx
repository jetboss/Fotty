"use client";

import Link from "next/link";
import { ArrowUpRight, BadgeDollarSign, ShieldCheck } from "lucide-react";
import { useEntitlement } from "@/components/EntitlementProvider";
import { trackEvent } from "@/lib/analytics";
import { cn } from "@/lib/utils";

type SponsoredPlacement = "home" | "p2p" | "watch";

const SPONSOR_HREF = process.env.NEXT_PUBLIC_SPONSOR_HREF || "/collab";
const SPONSOR_LABEL = process.env.NEXT_PUBLIC_SPONSOR_LABEL || "Sponsor";
const SPONSOR_TITLE = process.env.NEXT_PUBLIC_SPONSOR_TITLE || "Bring Fotty to match day";
const SPONSOR_COPY =
  process.env.NEXT_PUBLIC_SPONSOR_COPY ||
  "Watch party kits, community hubs, and sponsor placements for clubs, venues, and fan groups.";

export function SponsoredSlot({
  placement,
  compact = false,
  className,
}: {
  placement: SponsoredPlacement;
  compact?: boolean;
  className?: string;
}) {
  const entitlement = useEntitlement();
  if (entitlement.isPaid) return null;

  return (
    <Link
      href={SPONSOR_HREF}
      onClick={() => trackEvent("sponsor_slot_click", { placement, href: SPONSOR_HREF })}
      className={cn(
        "block rounded-lg border border-accent/20 bg-accent/10 px-4 py-4 transition-colors hover:bg-accent/15",
        className
      )}
    >
      <div className="flex items-center justify-between gap-4">
        <div className="flex min-w-0 items-center gap-3">
          <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-accent/15 text-accent">
            {placement === "watch" ? <ShieldCheck size={18} /> : <BadgeDollarSign size={18} />}
          </div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <p className="truncate text-sm font-black text-text-primary">{SPONSOR_TITLE}</p>
              <span className="rounded-full border border-accent/25 px-2 py-0.5 text-[10px] font-black uppercase text-accent">
                {SPONSOR_LABEL}
              </span>
            </div>
            {!compact && <p className="mt-1 line-clamp-2 text-xs font-medium leading-5 text-text-secondary">{SPONSOR_COPY}</p>}
          </div>
        </div>
        <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5 text-accent">
          <ArrowUpRight size={16} />
        </div>
      </div>
    </Link>
  );
}

