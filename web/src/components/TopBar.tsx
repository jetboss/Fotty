"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Heart, Search } from "lucide-react";
import { cn } from "@/lib/utils";

export function TopBar() {
  const pathname = usePathname();
  if (pathname.startsWith("/watch") || pathname.startsWith("/demo")) return null;

  return (
    <header className="sticky top-0 z-30 border-b border-white/5 bg-background/95 px-md pb-2 pt-[calc(0.75rem+env(safe-area-inset-top,0px))] backdrop-blur-xl lg:pl-[calc(104px+1rem)]">
      <div className="mx-auto flex max-w-[1440px] items-center justify-between gap-2">
        <Link
          href="/"
          className="min-w-0 shrink text-sm font-black tracking-[0.25em] text-white lg:pointer-events-none lg:invisible lg:w-0"
        >
          FOTTY
        </Link>

        <div className="ml-auto flex min-w-0 shrink-0 items-center gap-1.5 sm:gap-2">
          <HeaderIconLink
            href="/search"
            label="Search"
            active={pathname.startsWith("/search")}
            icon={<Search size={18} />}
          />
          <HeaderIconLink
            href="/favorites"
            label="Saved"
            active={pathname.startsWith("/favorites")}
            icon={<Heart size={18} />}
          />
        </div>
      </div>
    </header>
  );
}

function HeaderIconLink({
  href,
  label,
  active,
  icon,
}: {
  href: string;
  label: string;
  active: boolean;
  icon: ReactNode;
}) {
  const router = useRouter();
  const prefetch = () => router.prefetch(href);

  return (
    <Link
      href={href}
      prefetch
      onPointerEnter={prefetch}
      onTouchStart={prefetch}
      aria-label={label}
      className={cn(
        "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border transition-colors sm:h-10 sm:w-10",
        active
          ? "border-accent/40 bg-accent/10 text-accent"
          : "border-white/10 bg-surface text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
      )}
    >
      {icon}
    </Link>
  );
}
