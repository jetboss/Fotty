import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { LegalFooter } from "@/components/LegalFooter";

export const metadata = {
  title: "Privacy Policy | FOTTY",
  description: "How Fotty handles data across its iPhone, iPad, and web experiences.",
};

export default function PrivacyPage() {
  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary">
      <header className="space-y-4 px-md">
        <Link
          href="/settings"
          className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
          aria-label="Back to settings"
        >
          <ArrowLeft size={18} />
        </Link>
        <div className="space-y-2">
          <h1 className="text-4xl font-black">Privacy Policy</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">Last updated: August 29, 2026</p>
        </div>
      </header>

      <article className="space-y-6 px-md py-lg text-sm font-medium leading-7 text-text-secondary">
        <PolicySection title="Overview">
          Fotty is a sports discovery, match-day, playback, and Fantasy Premier League companion for iPhone, iPad, and
          the web. This policy explains what stays on your device and what leaves it when you use a network feature.
        </PolicySection>

        <PolicySection title="Data on your device">
          Your profile, followed teams, saved matches, reminders, appearance choices, local messages, recent match
          sessions, FPL manager ID, squad drafts, Coach history, and temporary data caches may be stored locally. They
          remain until you remove them, clear site data, or delete the app, subject to normal operating-system cleanup.
        </PolicySection>

        <PolicySection title="Accounts and sync">
          Fotty does not currently provide a Fotty cloud account or cross-device social sync. It does not ask for or
          transmit an FPL password. Your FPL manager ID is used only to request the public data that the official Fantasy
          Premier League service makes available for that manager.
        </PolicySection>

        <PolicySection title="FPL Smart Coach">
          Smart Coach is opt-in. When you send a question, Fotty may send the question, an installation identifier, your
          FPL manager ID, and a bounded summary of relevant squad, fixture, and recent-history data to Fotty&apos;s Cloudflare
          Worker. Questions that require model reasoning may then be processed by DeepSeek. Rules and scoring checks are
          calculated deterministically when possible. Fotty does not send your FPL password. Network providers may
          process standard request metadata such as IP address and timestamps to operate and protect their services.
        </PolicySection>

        <PolicySection title="Sports data and playback">
          Fixture listings, scores, team data, stream metadata, and playback requests may pass through Fotty services
          and third-party sports or player providers. A selected provider&apos;s player page is governed by that provider&apos;s
          terms and privacy practices. Content and availability can vary by source and region.
        </PolicySection>

        <PolicySection title="Notifications">
          Match and FPL deadline reminders are opt-in. Fotty schedules local notifications only after permission is
          granted. You can revoke notification permission in your device or browser settings.
        </PolicySection>

        <PolicySection title="Diagnostics">
          The iOS app keeps a bounded, redacted reliability history on your device. It excludes match names, manager
          IDs, stream URLs, credentials, and Coach prompts and is not uploaded automatically. It leaves your device only
          if you deliberately export and share it.
        </PolicySection>

        <PolicySection title="Your choices">
          You can stop following teams, remove saved items, clear supported local records, disable notifications, avoid
          Smart Coach, clear browser data, or delete Fotty. Questions or data requests can be sent through Fotty&apos;s
          published support channel.
        </PolicySection>

        <PolicySection title="Updates">
          We may update this policy as Fotty changes. The effective date above will change when the policy is revised.
        </PolicySection>
      </article>

      <LegalFooter />
    </main>
  );
}

function PolicySection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-2">
      <h2 className="text-base font-black text-text-primary">{title}</h2>
      <p>{children}</p>
    </section>
  );
}
