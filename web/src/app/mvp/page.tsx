"use client";

import Link from "next/link";
import React, { useMemo, useState } from "react";
import { ArrowLeft, BarChart3, BellRing, Handshake, HeartHandshake, RefreshCw } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { getCollabInquiries, getSupportPledges, getTrackedTeams } from "@/lib/storage";

const EVENTS_KEY = "fotty.web.events.v1";
const POCKETBASE_WRITE_TARGETS = [
  {
    title: "team_follows",
    detail: "Tracked team records for account sync and future push targeting",
  },
  {
    title: "match_reminders",
    detail: "Saved match reminders created from fixture cards",
  },
  {
    title: "partner_inquiries",
    detail: "Collab inquiries from venues, clubs, sponsors, and communities",
  },
  {
    title: "support_pledges",
    detail: "Supporter intent and pledge fallback before payment links are live",
  },
];

interface LocalSignal {
  createdAt?: string;
  at?: string;
  title?: string;
  packageTitle?: string;
  organization?: string;
  contact?: string;
  plan?: string;
  amount?: number;
  name?: string;
}

function readList<T>(key: string): T[] {
  if (typeof window === "undefined") return [];
  try {
    const parsed = JSON.parse(window.localStorage.getItem(key) || "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function loadSignals() {
  return {
    trackedTeams: getTrackedTeams(),
    collabInquiries: getCollabInquiries(),
    supportPledges: getSupportPledges(),
    events: readList<LocalSignal & { name?: string; payload?: Record<string, unknown> }>(EVENTS_KEY),
  };
}

export default function MVPPage() {
  const { session } = useAuth();
  const [snapshot, setSnapshot] = useState(loadSignals);
  const latestEvents = useMemo(() => snapshot.events.slice(0, 8), [snapshot.events]);

  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary">
      <header className="space-y-4 px-md">
        <div className="flex items-center justify-between gap-3">
          <Link
            href="/settings"
            className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
            aria-label="Back to settings"
          >
            <ArrowLeft size={18} />
          </Link>
          <button
            type="button"
            onClick={() => setSnapshot(loadSignals())}
            className="inline-flex h-10 items-center gap-2 rounded-full border border-white/10 bg-surface px-4 text-xs font-black text-text-primary"
          >
            <RefreshCw size={14} />
            Refresh
          </button>
        </div>

        <div className="space-y-2">
          <h1 className="text-4xl font-black">Operations Signals</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            Internal signal console for team tracking, collab inquiries, supporter intent, and product events.
          </p>
        </div>
      </header>

      <div className="space-y-4 px-md py-lg">
        <div className="grid gap-3 sm:grid-cols-4">
          <Metric icon={BellRing} label="Tracked teams" value={snapshot.trackedTeams.length} />
          <Metric icon={Handshake} label="Collab inquiries" value={snapshot.collabInquiries.length} />
          <Metric icon={HeartHandshake} label="Support pledges" value={snapshot.supportPledges.length} />
          <Metric icon={BarChart3} label="Local events" value={snapshot.events.length} />
        </div>

        <section className="rounded-xl border border-white/5 bg-surface p-4">
          <div className="flex items-start gap-3">
            <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-accent/15 text-accent">
              <BarChart3 size={17} />
            </div>
            <div className="space-y-3">
              <div>
                <p className="text-sm font-black text-text-primary">Launch readiness switches</p>
                <p className="mt-1 text-xs font-medium leading-5 text-text-secondary">
                  These external switches keep account-backed features, payments, and browser messaging ready for live operation.
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                <ReadinessPill label={session?.provider === "pocketbase" ? "PocketBase session active" : "PocketBase session needed"} active={session?.provider === "pocketbase"} />
                <ReadinessPill label="Payment links" />
                <ReadinessPill label={session?.provider === "pocketbase" ? "Real auth active" : "Local auth fallback"} active={session?.provider === "pocketbase"} />
                <ReadinessPill label="Browser push" />
              </div>
            </div>
          </div>
        </section>

        <SignalSection title="Tracked Teams" empty="No tracked teams saved yet.">
          {snapshot.trackedTeams.map((team) => (
            <SignalRow key={team.id} title={team.name} detail={[team.sport, team.league].filter(Boolean).join(" · ")} />
          ))}
        </SignalSection>

        <SignalSection title="PocketBase Write Targets" empty="No write targets configured.">
          {POCKETBASE_WRITE_TARGETS.map((target) => (
            <SignalRow key={target.title} title={target.title} detail={target.detail} />
          ))}
        </SignalSection>

        <SignalSection title="Collab Inquiries" empty="No collab inquiries saved yet.">
          {snapshot.collabInquiries.map((entry, index) => (
            <SignalRow
              key={`${entry.createdAt || "collab"}-${index}`}
              title={entry.organization || entry.packageTitle || "Collab inquiry"}
              detail={[entry.packageTitle, entry.contact].filter(Boolean).join(" · ")}
            />
          ))}
        </SignalSection>

        <SignalSection title="Support Pledges" empty="No support pledges saved yet.">
          {snapshot.supportPledges.map((entry, index) => (
            <SignalRow
              key={`${entry.createdAt || "support"}-${index}`}
              title={entry.title || entry.plan || "Support pledge"}
              detail={[entry.amount ? `$${entry.amount}` : undefined, entry.contact].filter(Boolean).join(" · ")}
            />
          ))}
        </SignalSection>

        <SignalSection title="Recent Events" empty="No local events captured yet.">
          {latestEvents.map((event, index) => (
            <SignalRow
              key={`${event.at || "event"}-${index}`}
              title={event.name || "Event"}
              detail={event.at ? new Date(event.at).toLocaleString() : undefined}
            />
          ))}
        </SignalSection>
      </div>
    </main>
  );
}

function Metric({ icon: Icon, label, value }: { icon: typeof BellRing; label: string; value: number }) {
  return (
    <section className="rounded-xl border border-white/5 bg-surface p-4">
      <div className="flex items-center gap-2 text-accent">
        <Icon size={16} />
        <p className="text-xs font-black uppercase">{label}</p>
      </div>
      <p className="mt-4 text-3xl font-black text-white">{value}</p>
    </section>
  );
}

function SignalSection({ title, empty, children }: { title: string; empty: string; children: React.ReactNode }) {
  const hasChildren = React.Children.count(children) > 0;

  return (
    <section className="overflow-hidden rounded-xl border border-white/5 bg-surface">
      <div className="border-b border-white/5 px-4 py-3">
        <h2 className="text-sm font-black text-text-primary">{title}</h2>
      </div>
      {hasChildren ? children : <p className="p-4 text-xs font-medium leading-6 text-text-secondary">{empty}</p>}
    </section>
  );
}

function SignalRow({ title, detail }: { title: string; detail?: string }) {
  return (
    <div className="border-b border-white/5 px-4 py-3 last:border-b-0">
      <p className="truncate text-sm font-bold text-text-primary">{title}</p>
      {detail && <p className="mt-1 truncate text-xs font-medium text-text-tertiary">{detail}</p>}
    </div>
  );
}

function ReadinessPill({ label, active = false }: { label: string; active?: boolean }) {
  return (
    <span className={active
      ? "rounded-full border border-live/25 bg-live/10 px-3 py-1 text-[11px] font-bold text-live"
      : "rounded-full border border-white/10 bg-white/5 px-3 py-1 text-[11px] font-bold text-text-secondary"}
    >
      {label}
    </span>
  );
}
