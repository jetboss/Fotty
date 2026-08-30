"use client";

import Link from "next/link";
import React, { useState } from "react";
import {
  ArrowLeft,
  Building2,
  Check,
  Megaphone,
  QrCode,
  ShieldCheck,
  Trophy,
  Users,
} from "lucide-react";
import { trackEvent } from "@/lib/analytics";
import { saveCollabInquiry } from "@/lib/storage";
import { cn } from "@/lib/utils";

type CollabPackageId = "watch-party" | "community-hub" | "sponsor" | "local-club";

const packages = [
  {
    id: "watch-party",
    icon: QrCode,
    title: "Watch Party Kit",
    label: "Venue",
    summary: "A shareable match hub for bars, pop-ups, and one-night match events.",
    includes: ["Fixture board", "QR invite", "Venue notes", "Reminder handoff"],
  },
  {
    id: "community-hub",
    icon: Users,
    title: "Community Hub",
    label: "Groups",
    summary: "A lightweight Fotty home for fan communities tracking the same teams.",
    includes: ["Tracked clubs", "Shared match board", "Member reminders", "Feedback loop"],
  },
  {
    id: "sponsor",
    icon: Megaphone,
    title: "Sponsor Placement",
    label: "Brand",
    summary: "Tasteful match-day placement that supports Fotty without blocking playback.",
    includes: ["Support placement", "Match-day context", "Local campaign note", "Intent reporting"],
  },
  {
    id: "local-club",
    icon: Trophy,
    title: "Local Club Pilot",
    label: "Club",
    summary: "A pilot for clubs and small leagues that need fixtures, alerts, and presence.",
    includes: ["Club page", "Fixture alerts", "Team tracking", "Metadata cleanup"],
  },
] satisfies Array<{
  id: CollabPackageId;
  icon: typeof QrCode;
  title: string;
  label: string;
  summary: string;
  includes: string[];
}>;

export default function CollabPage() {
  const [selectedId, setSelectedId] = useState<CollabPackageId>("watch-party");
  const [organization, setOrganization] = useState("");
  const [contact, setContact] = useState("");
  const [region, setRegion] = useState("");
  const [audienceSize, setAudienceSize] = useState("");
  const [useCase, setUseCase] = useState("");
  const [matchFocus, setMatchFocus] = useState("");
  const [saved, setSaved] = useState(false);
  const selected = packages.find((item) => item.id === selectedId) || packages[0];

  const saveInquiry = () => {
    const entry = {
      packageId: selected.id,
      packageTitle: selected.title,
      organization: organization.trim() || undefined,
      contact: contact.trim() || undefined,
      region: region.trim() || undefined,
      audienceSize: audienceSize.trim() || undefined,
      useCase: useCase.trim() || undefined,
      matchFocus: matchFocus.trim() || undefined,
      createdAt: new Date().toISOString(),
    };

    try {
      saveCollabInquiry(entry);
      setSaved(true);
      trackEvent("collab_inquiry_saved", {
        packageId: selected.id,
        hasContact: Boolean(entry.contact),
        audienceSize: entry.audienceSize,
      });
    } catch {
      setSaved(false);
    }
  };

  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary">
      <header className="space-y-5 px-md">
        <Link
          href="/"
          className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
          aria-label="Back home"
        >
          <ArrowLeft size={18} />
        </Link>

        <div className="max-w-3xl space-y-3">
          <div className="inline-flex items-center gap-2 rounded-full border border-accent/25 bg-accent/10 px-3 py-1 text-xs font-black text-accent">
            <Building2 size={13} />
            Fotty Collab
          </div>
          <h1 className="text-4xl font-black leading-tight text-white sm:text-5xl">Bring Fotty to your match day.</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            Collab is the partner lane for venues, fan communities, clubs, and sponsors who want a practical match-day surface.
          </p>
        </div>
      </header>

      <div className="grid gap-4 px-md py-lg lg:grid-cols-[minmax(0,1fr)_440px]">
        <section className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            {packages.map((item) => (
              <CollabPackage
                key={item.id}
                item={item}
                selected={item.id === selectedId}
                onSelect={() => {
                  setSelectedId(item.id);
                  setSaved(false);
                }}
              />
            ))}
          </div>

          <section className="rounded-xl border border-white/5 bg-surface p-4">
            <div className="flex items-start gap-3">
              <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-live/10 text-live">
                <ShieldCheck size={17} />
              </div>
              <div className="space-y-1">
                <p className="text-sm font-bold text-text-primary">Partner promise</p>
                <p className="text-xs font-medium leading-6 text-text-secondary">
                  Start with a clean inquiry, a match-day plan, and a clear path to launch support.
                </p>
              </div>
            </div>
          </section>
        </section>

        <aside className="h-fit rounded-xl border border-white/5 bg-surface p-4 lg:sticky lg:top-24">
          <div className="space-y-4">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-xs font-bold uppercase text-text-tertiary">Selected collab</p>
                <h2 className="mt-1 text-xl font-black text-white">{selected.title}</h2>
                <p className="mt-1 text-xs font-medium leading-5 text-text-secondary">{selected.summary}</p>
              </div>
              {saved && (
                <div className="inline-flex items-center gap-1.5 rounded-full bg-live/10 px-3 py-1 text-xs font-black text-live">
                  <Check size={13} />
                  Saved
                </div>
              )}
            </div>

            <div className="grid gap-3">
              <Field label="Organization" value={organization} onChange={setOrganization} placeholder="Venue, club, community, or brand" />
              <Field label="Contact" value={contact} onChange={setContact} placeholder="Email or best contact" />
              <Field label="City / Region" value={region} onChange={setRegion} placeholder="Where this collab happens" />
              <Field label="Audience size" value={audienceSize} onChange={setAudienceSize} placeholder="20, 100, 500+" />
              <Field label="Match focus" value={matchFocus} onChange={setMatchFocus} placeholder="Teams, league, or event type" />
              <div className="space-y-2">
                <label htmlFor="collab-use-case" className="text-xs font-bold uppercase text-text-tertiary">
                  What are you trying to do?
                </label>
                <textarea
                  id="collab-use-case"
                  value={useCase}
                  onChange={(event) => setUseCase(event.target.value)}
                  placeholder="Example: host Arsenal match days every weekend with a QR link and reminders."
                  className="min-h-28 w-full rounded-lg border border-white/10 bg-background px-4 py-3 text-sm font-semibold text-text-primary outline-none placeholder:text-text-tertiary"
                />
              </div>
            </div>

            <div className="grid gap-2">
              <button
                type="button"
                onClick={saveInquiry}
                className="inline-flex min-h-12 items-center justify-center gap-2 rounded-lg accent-gradient px-4 text-sm font-black text-white"
              >
                Save collab inquiry
                <Check size={15} />
              </button>
              <Link
                href="/feedback?intent=partner"
                className="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-white/10 bg-white/5 px-4 text-xs font-bold text-text-primary"
              >
                Send details instead
              </Link>
            </div>
          </div>
        </aside>
      </div>
    </main>
  );
}

function CollabPackage({
  item,
  selected,
  onSelect,
}: {
  item: (typeof packages)[number];
  selected: boolean;
  onSelect: () => void;
}) {
  const Icon = item.icon;

  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "rounded-xl border p-4 text-left transition-colors",
        selected ? "border-accent/40 bg-accent/10" : "border-white/5 bg-surface hover:bg-surface-elevated"
      )}
      aria-pressed={selected}
    >
      <div className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-full bg-white/5 text-accent">
            <Icon size={18} />
          </div>
          <span className={cn("rounded-full px-3 py-1 text-[11px] font-black", selected ? "bg-accent text-white" : "bg-white/5 text-accent")}>
            {item.label}
          </span>
        </div>
        <div className="space-y-1">
          <h2 className="text-sm font-black text-text-primary">{item.title}</h2>
          <p className="text-xs font-medium leading-6 text-text-secondary">{item.summary}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {item.includes.map((label) => (
            <span key={label} className="rounded-full border border-white/10 bg-white/5 px-3 py-1 text-[11px] font-bold text-text-secondary">
              {label}
            </span>
          ))}
        </div>
      </div>
    </button>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  const id = `collab-${label.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`;

  return (
    <div className="space-y-2">
      <label htmlFor={id} className="text-xs font-bold uppercase text-text-tertiary">
        {label}
      </label>
      <input
        id={id}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        className="min-h-11 w-full rounded-lg border border-white/10 bg-background px-4 text-sm font-semibold text-text-primary outline-none placeholder:text-text-tertiary"
      />
    </div>
  );
}
