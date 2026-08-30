import Link from "next/link";
import { getMatchFeed } from "@/lib/server/match-feed";
import { ArrowRight, Radio, Smartphone, Tv } from "lucide-react";
import { LegalFooter } from "@/components/LegalFooter";

export const revalidate = 45;

export const metadata = {
  title: "Welcome to Fotty",
  description: "Live sports in your browser. The Fotty iOS app is the full native match-day experience.",
};

export default async function WelcomePage() {
  const matches = await getMatchFeed().catch(() => []);
  const liveCount = matches.filter((match) => match.status === "Live").length;

  return (
    <main className="min-h-dvh bg-background pt-12 text-text-primary">
      <div className="mx-auto max-w-3xl space-y-10 px-md py-lg">
        <header className="space-y-4">
          <p className="text-xs font-black uppercase tracking-[0.25em] text-accent">FOTTY</p>
          <h1 className="text-4xl font-black leading-tight text-white sm:text-5xl">Match day in your browser.</h1>
          <p className="text-sm font-medium leading-7 text-text-secondary sm:text-base">
            Fotty Web is coverage for when you need a quick watch in the browser. The Fotty iOS app is the primary
            experience — cinema Home, On now glance, source reliability, and the full native player.
          </p>
        </header>

        <section className="grid gap-3 sm:grid-cols-3">
          <Feature icon={Radio} title="On now" detail={liveCount > 0 ? `${liveCount} live now` : "Live and upcoming fixtures"} />
          <Feature icon={Tv} title="Watch fast" detail="Open a match and switch sources calmly" />
          <Feature icon={Smartphone} title="Best on iOS" detail="Native player, glance strip, and match hub" />
        </section>

        <section className="flex flex-col gap-3 sm:flex-row">
          <Link
            href="/"
            className="inline-flex min-h-12 flex-1 items-center justify-center gap-2 rounded-full accent-gradient px-6 text-sm font-black text-white"
          >
            Enter Fotty Home
            <ArrowRight size={16} />
          </Link>
          <Link
            href="/search"
            className="inline-flex min-h-12 flex-1 items-center justify-center rounded-full border border-white/10 bg-surface px-6 text-sm font-black text-text-primary"
          >
            Discover fixtures
          </Link>
        </section>

        <p className="text-center text-xs font-medium leading-6 text-text-tertiary">
          Prefer the app when you can. Web stays available for coverage on any device.
        </p>

        <LegalFooter />
      </div>
    </main>
  );
}

function Feature({ icon: Icon, title, detail }: { icon: typeof Radio; title: string; detail: string }) {
  return (
    <div className="rounded-xl border border-white/5 bg-surface p-4">
      <div className="mb-3 grid h-10 w-10 place-items-center rounded-full bg-accent/15 text-accent">
        <Icon size={18} />
      </div>
      <p className="text-sm font-black text-white">{title}</p>
      <p className="mt-1 text-xs font-medium leading-5 text-text-secondary">{detail}</p>
    </div>
  );
}
