"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { motion, AnimatePresence } from "framer-motion";
import {
  ArrowRight,
  Radio,
  Shield,
  ChevronRight,
} from "lucide-react";
import { cn } from "@/lib/utils";

/* ─────────────────────────────────────────────
   SAMPLE FIXTURE DATA
   ───────────────────────────────────────────── */

const FIXTURES = [
  {
    id: "1",
    home: "Arsenal",
    away: "Chelsea",
    league: "PL",
    status: "live" as const,
    minute: "67'",
    score: "2 — 1",
    sources: 4,
  },
  {
    id: "2",
    home: "Barcelona",
    away: "Real Madrid",
    league: "LL",
    status: "soon" as const,
    time: "21:00",
    sources: 3,
  },
  {
    id: "3",
    home: "Bayern",
    away: "Dortmund",
    league: "BL",
    status: "soon" as const,
    time: "18:30",
    sources: 2,
  },
  {
    id: "4",
    home: "Milan",
    away: "Inter",
    league: "SA",
    status: "soon" as const,
    time: "20:45",
    sources: 5,
  },
  {
    id: "5",
    home: "PSG",
    away: "Marseille",
    league: "L1",
    status: "live" as const,
    minute: "34'",
    score: "1 — 0",
    sources: 3,
  },
];

/* ─────────────────────────────────────────────
   MAIN COMPONENT
   ───────────────────────────────────────────── */

export function DemoLanding() {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden bg-[#060810]">
      {/* ── Ambient stadium glow ── */}
      <div className="pointer-events-none absolute inset-0 z-0">
        <div className="absolute left-1/2 top-0 h-[70vh] w-[120vw] -translate-x-1/2 -translate-y-[30%] bg-[radial-gradient(ellipse_at_center,rgba(224,31,71,0.07)_0%,rgba(59,130,246,0.04)_40%,transparent_70%)]" />
        <div className="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/[0.06] to-transparent" />
      </div>

      {/* ── Pitch grid lines (subtle) ── */}
      <div className="pointer-events-none absolute inset-0 z-0 opacity-[0.025]">
        <div className="absolute left-1/2 top-1/2 h-[40vh] w-[40vh] -translate-x-1/2 -translate-y-1/2 rounded-full border border-white" />
        <div className="absolute left-1/2 top-0 h-full w-px bg-white" />
      </div>

      {/* ── Top bar ── */}
      <header className="relative z-20 flex items-center justify-between px-6 py-5 sm:px-10">
        <Link href="/demo" className="text-sm font-black tracking-[0.35em] text-white">
          FOTTY
        </Link>
        <Link
          href="/"
          className="group inline-flex items-center gap-2 rounded-full bg-white px-5 py-2.5 text-[13px] font-bold text-[#060810] transition-all hover:shadow-[0_0_24px_rgba(255,255,255,0.15)] active:scale-[0.97]"
        >
          Open Fotty
          <ArrowRight size={14} className="transition-transform group-hover:translate-x-0.5" />
        </Link>
      </header>

      {/* ── Hero content ── */}
      <main className="relative z-10 flex flex-1 items-center px-6 pb-10 sm:px-10 lg:px-16">
        <div className="mx-auto grid w-full max-w-[1400px] items-center gap-10 lg:grid-cols-[1fr_minmax(420px,520px)] lg:gap-20">
          {/* Left: statement */}
          <div className="max-w-xl">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={mounted ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.6, delay: 0.1, ease: [0.25, 0.46, 0.45, 0.94] as const }}
            >
              <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-emerald-500/20 bg-emerald-500/8 px-3.5 py-1.5">
                <span className="relative flex h-2 w-2">
                  <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
                  <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-400" />
                </span>
                <span className="text-[11px] font-bold text-emerald-400">Sports only</span>
              </div>
            </motion.div>

            <motion.h1
              initial={{ opacity: 0, y: 24 }}
              animate={mounted ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.7, delay: 0.2, ease: [0.25, 0.46, 0.45, 0.94] as const }}
              className="text-[clamp(2.5rem,6vw,4.5rem)] font-black leading-[0.92] tracking-tight text-white"
            >
              Match day,
              <br />
              sorted.
            </motion.h1>

            <motion.p
              initial={{ opacity: 0, y: 20 }}
              animate={mounted ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.6, delay: 0.35, ease: [0.25, 0.46, 0.45, 0.94] as const }}
              className="mt-5 max-w-md text-[15px] font-medium leading-7 text-[#8a919e]"
            >
              Live fixtures, source status, highlights, and fan tools — one surface, no&nbsp;hunting.
            </motion.p>

            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={mounted ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.6, delay: 0.5, ease: [0.25, 0.46, 0.45, 0.94] as const }}
              className="mt-8 flex items-center gap-4"
            >
              <Link
                href="/"
                className="group inline-flex items-center gap-2.5 rounded-full bg-gradient-to-r from-accent to-rose-600 px-7 py-3.5 text-sm font-bold text-white shadow-[0_12px_40px_rgba(224,31,71,0.3)] transition-all hover:-translate-y-0.5 hover:shadow-[0_16px_48px_rgba(224,31,71,0.4)] active:scale-[0.97]"
              >
                Open Fotty
                <ArrowRight
                  size={15}
                  className="transition-transform group-hover:translate-x-0.5"
                />
              </Link>
              <Link
                href="/welcome"
                className="text-sm font-semibold text-[#8a919e] transition-colors hover:text-white"
              >
                Learn more
              </Link>
            </motion.div>
          </div>

          {/* Right: live ticker card */}
          <motion.div
            initial={{ opacity: 0, scale: 0.96, y: 12 }}
            animate={mounted ? { opacity: 1, scale: 1, y: 0 } : {}}
            transition={{ duration: 0.8, delay: 0.4, ease: [0.25, 0.46, 0.45, 0.94] as const }}
            className="hidden lg:block"
          >
            <LiveTicker />
          </motion.div>
        </div>
      </main>

      {/* ── Mobile ticker (below hero text on small screens) ── */}
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={mounted ? { opacity: 1, y: 0 } : {}}
        transition={{ duration: 0.7, delay: 0.5, ease: [0.25, 0.46, 0.45, 0.94] as const }}
        className="relative z-10 px-6 pb-8 lg:hidden"
      >
        <LiveTickerMobile />
      </motion.div>

      {/* ── Bottom strip ── */}
      <footer className="relative z-10 border-t border-white/[0.04] px-6 py-4 sm:px-10">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between">
          <div className="flex items-center gap-5 text-[11px] font-semibold text-[#4a5060]">
            <Link href="/privacy" className="transition-colors hover:text-white/60">Privacy</Link>
            <Link href="/terms" className="transition-colors hover:text-white/60">Terms</Link>
            <Link href="/help" className="transition-colors hover:text-white/60">Help</Link>
          </div>
          <p className="text-[11px] font-medium text-[#4a5060]">Football only. No exceptions.</p>
        </div>
      </footer>
    </div>
  );
}

/* ─────────────────────────────────────────────
   LIVE TICKER — Desktop
   ───────────────────────────────────────────── */

function LiveTicker() {
  const [activeIdx, setActiveIdx] = useState(0);
  const active = FIXTURES[activeIdx];

  // Auto-rotate
  useEffect(() => {
    const interval = setInterval(() => {
      setActiveIdx((prev) => (prev + 1) % FIXTURES.length);
    }, 3500);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="relative">
      {/* Outer glow */}
      <div className="absolute -inset-4 rounded-3xl bg-gradient-to-br from-accent/8 via-transparent to-blue-500/6 blur-2xl" />

      <div className="relative overflow-hidden rounded-2xl border border-white/[0.08] bg-[#0b0e16] shadow-[0_40px_100px_rgba(0,0,0,0.6)]">
        {/* Header bar */}
        <div className="flex items-center justify-between border-b border-white/[0.06] px-5 py-3">
          <div className="flex items-center gap-2">
            <Radio size={13} className="text-accent animate-pulse" />
            <span className="text-[11px] font-bold uppercase tracking-widest text-[#5a6170]">
              Matchday
            </span>
          </div>
          <span className="text-[10px] font-bold text-[#3d4350]">
            {FIXTURES.filter((f) => f.status === "live").length} live
          </span>
        </div>

        {/* Featured match */}
        <div className="border-b border-white/[0.04] p-5">
          <AnimatePresence mode="wait">
            <motion.div
              key={active.id}
              initial={{ opacity: 0, x: 8 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -8 }}
              transition={{ duration: 0.3 }}
            >
              <div className="flex items-center justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    {active.status === "live" ? (
                      <span className="flex items-center gap-1.5 text-[10px] font-bold text-accent">
                        <span className="h-1.5 w-1.5 rounded-full bg-accent animate-pulse" />
                        LIVE · {active.minute}
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold text-[#5a6170]">
                        Today {active.time}
                      </span>
                    )}
                    <span className="rounded border border-white/[0.06] bg-white/[0.03] px-1.5 py-0.5 text-[9px] font-bold text-[#5a6170]">
                      {active.league}
                    </span>
                  </div>
                  <p className="mt-2 text-lg font-black text-white">
                    {active.home} vs {active.away}
                  </p>
                  {active.score && (
                    <p className="mt-1 text-2xl font-black tabular-nums tracking-tight text-white">
                      {active.score}
                    </p>
                  )}
                </div>
                <div className="text-right">
                  <SourceBadge count={active.sources} />
                </div>
              </div>
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Fixture list */}
        <div className="divide-y divide-white/[0.03]">
          {FIXTURES.map((fixture, i) => (
            <button
              key={fixture.id}
              type="button"
              onClick={() => setActiveIdx(i)}
              className={cn(
                "flex w-full items-center justify-between px-5 py-3 text-left transition-colors",
                i === activeIdx
                  ? "bg-white/[0.03]"
                  : "hover:bg-white/[0.02]"
              )}
            >
              <div className="flex items-center gap-3">
                {fixture.status === "live" ? (
                  <span className="h-1.5 w-1.5 rounded-full bg-accent animate-pulse" />
                ) : (
                  <span className="h-1.5 w-1.5 rounded-full bg-[#2a2f3a]" />
                )}
                <span className={cn(
                  "text-xs font-bold",
                  i === activeIdx ? "text-white" : "text-[#6b7280]"
                )}>
                  {fixture.home} vs {fixture.away}
                </span>
              </div>
              <div className="flex items-center gap-2">
                {fixture.status === "live" && fixture.score ? (
                  <span className="text-xs font-black tabular-nums text-white">{fixture.score}</span>
                ) : (
                  <span className="text-[10px] font-bold text-[#4a5060]">{fixture.time}</span>
                )}
                <ChevronRight size={12} className="text-[#3d4350]" />
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   LIVE TICKER — Mobile (compact horizontal)
   ───────────────────────────────────────────── */

function LiveTickerMobile() {
  return (
    <div className="no-scrollbar -mx-6 flex gap-2.5 overflow-x-auto px-6 pb-2">
      {FIXTURES.map((fixture) => (
        <div
          key={fixture.id}
          className={cn(
            "shrink-0 rounded-xl border px-4 py-3",
            fixture.status === "live"
              ? "border-accent/20 bg-accent/[0.06]"
              : "border-white/[0.06] bg-white/[0.02]"
          )}
          style={{ minWidth: "200px" }}
        >
          <div className="flex items-center justify-between">
            {fixture.status === "live" ? (
              <span className="flex items-center gap-1.5 text-[10px] font-bold text-accent">
                <span className="h-1.5 w-1.5 rounded-full bg-accent animate-pulse" />
                {fixture.minute}
              </span>
            ) : (
              <span className="text-[10px] font-bold text-[#5a6170]">{fixture.time}</span>
            )}
            <span className="text-[9px] font-bold text-[#4a5060]">{fixture.league}</span>
          </div>
          <p className="mt-1.5 text-xs font-black text-white">
            {fixture.home} vs {fixture.away}
          </p>
          {fixture.score && (
            <p className="mt-0.5 text-sm font-black tabular-nums text-white">{fixture.score}</p>
          )}
          <div className="mt-2">
            <SourceBadge count={fixture.sources} compact />
          </div>
        </div>
      ))}
    </div>
  );
}

/* ─────────────────────────────────────────────
   SOURCE BADGE
   ───────────────────────────────────────────── */

function SourceBadge({ count, compact = false }: { count: number; compact?: boolean }) {
  return (
    <div className={cn(
      "inline-flex items-center gap-1.5 rounded-full border border-emerald-500/20 bg-emerald-500/8",
      compact ? "px-2 py-0.5" : "px-2.5 py-1"
    )}>
      <Shield size={compact ? 9 : 10} className="text-emerald-400" />
      <span className={cn(
        "font-bold text-emerald-400",
        compact ? "text-[9px]" : "text-[10px]"
      )}>
        {count} stable
      </span>
    </div>
  );
}
