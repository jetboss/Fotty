import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { LegalFooter } from "@/components/LegalFooter";

export const metadata = {
  title: "Terms of Use | FOTTY",
  description: "Terms for using Fotty sports, playback, and FPL features.",
};

export default function TermsPage() {
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
          <h1 className="text-4xl font-black">Terms of Use</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">Last updated: August 29, 2026</p>
        </div>
      </header>

      <article className="space-y-6 px-md py-lg text-sm font-medium leading-7 text-text-secondary">
        <PolicySection title="Service">
          Fotty provides sports discovery, match context, playback tools, reminders, and Fantasy Premier League planning
          features on supported Apple devices and the web. It is currently beta software, and features may change.
        </PolicySection>

        <PolicySection title="Acceptable use">
          You agree not to abuse the service, attempt unauthorized access, evade access controls, scrape at scale,
          redistribute protected content, or interfere with playback or Coach infrastructure. Fotty may limit access
          that harms reliability, providers, or other users.
        </PolicySection>

        <PolicySection title="Beta access and entitlements">
          Internal or beta access is personal, revocable, and may expire with a build. Any future paid entitlement will
          be governed by the purchase channel and the account used to purchase it. Beta access does not promise a
          permanent subscription or public release.
        </PolicySection>

        <PolicySection title="Fantasy Premier League">
          Fotty uses public official FPL data to provide analysis and planning. Local squad drafts and transfer scenarios
          do not make changes in the official FPL app or website. You remain responsible for submitting official team,
          transfer, captain, chip, and lineup decisions before the deadline.
        </PolicySection>

        <PolicySection title="Coach guidance">
          Smart Coach output is assistance, not an official ruling or a guarantee of points, rank, availability, or
          results. Deterministic rules checks take priority, but you should verify important decisions with the official
          FPL service.
        </PolicySection>

        <PolicySection title="Third-party content">
          Broadcast sources, player pages, fixtures, scores, team assets, and other metadata may originate from third
          parties. You are responsible for complying with the law and provider terms in your region. Fotty does not
          guarantee that any particular source is authorized or available in your location.
        </PolicySection>

        <PolicySection title="Disclaimer">
          Fotty is provided &quot;as is&quot;. We do not warrant uninterrupted playback, complete schedules, error-free sports
          data, or successful FPL outcomes. To the extent permitted by law, use is at your own risk.
        </PolicySection>

        <PolicySection title="Contact">
          Questions about these terms can be sent through the in-app feedback page or your published support email when configured.
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
