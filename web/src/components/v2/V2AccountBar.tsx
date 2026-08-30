"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Crown, Heart, LogIn, LogOut } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { useEntitlement } from "@/components/EntitlementProvider";
import { isAccountsEnabled } from "@/lib/accounts";
import { v2FavoritesPath } from "@/lib/v2/preview";
import { cn } from "@/lib/utils";

const authCtaClass =
  "fotty-v2-auth-cta inline-flex h-9 shrink-0 items-center justify-center gap-1.5 rounded-full px-3 text-[11px] font-bold text-white shadow-[0_1px_0_rgba(255,255,255,0.12)_inset] accent-gradient transition hover:brightness-110 sm:text-xs";
export function V2AccountBar({ className }: { className?: string }) {
  const router = useRouter();
  const { session, signOut } = useAuth();
  const entitlement = useEntitlement();
  const accountsEnabled = isAccountsEnabled();
  return (
    <div className={cn("flex shrink-0 items-center gap-1.5", className)}>
      <Link
        href={v2FavoritesPath()}
        prefetch
        className="inline-flex h-9 w-9 items-center justify-center rounded-full text-zinc-300 transition hover:bg-white/10 hover:text-white"
        aria-label="Saved"
      >
        <Heart size={17} />
      </Link>
    </div>
  );
}
