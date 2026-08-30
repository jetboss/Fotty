import Link from "next/link";
import { ArrowLeft, ArrowUpRight, HeartHandshake, Rocket, Wallet } from "lucide-react";

const monthlyHref = process.env.NEXT_PUBLIC_SUPPORT_MONTHLY_URL;
const oneTimeHref = process.env.NEXT_PUBLIC_SUPPORT_ONE_TIME_URL;
const partnerHref = process.env.NEXT_PUBLIC_SUPPORT_PARTNER_URL;
const supportEmail = process.env.NEXT_PUBLIC_SUPPORT_EMAIL;

const partnerContactHref =
  partnerHref ||
  (supportEmail ? `mailto:${supportEmail}?subject=${encodeURIComponent("Fotty partnership")}` : undefined);

export default function SupportPage() {
  const hasRecurringSupport = Boolean(monthlyHref);
  const hasOneTimeSupport = Boolean(oneTimeHref);
  const hasPartnerSupport = Boolean(partnerContactHref);
  const hasAnySupportLink = hasRecurringSupport || hasOneTimeSupport || hasPartnerSupport;

  return (
    <main className="min-h-screen bg-background pb-32 pt-12 text-text-primary">
      <header className="space-y-4 px-md">
        <Link
          href="/settings"
          className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface text-text-primary"
          aria-label="Back to settings"
        >
          <ArrowLeft size={18} />
        </Link>

        <div className="space-y-2">
          <h1 className="text-4xl font-black">Support Fotty</h1>
          <p className="max-w-2xl text-sm font-medium leading-6 text-text-secondary">
            Support helps fund polish, reliability work, install improvements, and the small details that make Fotty feel premium. It does not change what appears in the live board.
          </p>
        </div>
      </header>

      <div className="space-y-4 px-md py-lg">
        {hasRecurringSupport && (
          <SupportOption
            icon={HeartHandshake}
            title="Patreon Supporter"
            subtitle="A recurring way to back the product, stay close to the roadmap, and help fund continued polish."
            href={monthlyHref}
            actionLabel="Join monthly"
          />
        )}

        {hasOneTimeSupport && (
          <SupportOption
            icon={Wallet}
            title="One-Time Support"
            subtitle="A one-time contribution for people who want to help without signing up for anything recurring."
            href={oneTimeHref}
            actionLabel="Leave a tip"
          />
        )}

        {hasPartnerSupport && (
          <SupportOption
            icon={Rocket}
            title="Venue or Partner"
            subtitle="For venues, sponsors, or anyone who wants to help Fotty grow through a bigger collaboration."
            href={partnerContactHref}
            actionLabel="Start a conversation"
          />
        )}

        <section className="rounded-xl border border-white/5 bg-surface p-4">
          <p className="text-sm font-bold text-text-primary">What support funds</p>
          <p className="mt-2 text-xs font-medium leading-6 text-text-secondary">
            Support goes toward product development, infrastructure, device testing, and making Fotty faster and easier to use.
          </p>
        </section>

        {!hasAnySupportLink && (
          <section className="rounded-xl border border-white/5 bg-surface p-4">
            <p className="text-sm font-bold text-text-primary">Support options are being prepared</p>
            <p className="mt-2 text-xs font-medium leading-6 text-text-secondary">
              This page is ready for monthly support, one-time tips, and partnership outreach as soon as those links are configured.
            </p>
          </section>
        )}
      </div>
    </main>
  );
}

function SupportOption({
  icon: Icon,
  title,
  subtitle,
  href,
  actionLabel,
}: {
  icon: typeof HeartHandshake;
  title: string;
  subtitle: string;
  href?: string;
  actionLabel: string;
}) {
  const content = (
    <section className="rounded-xl border border-white/5 bg-surface p-4 transition-colors hover:bg-surface-elevated">
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-3">
          <div className="grid h-11 w-11 place-items-center rounded-full bg-white/5 text-accent">
            <Icon size={18} />
          </div>
          <div className="space-y-1">
            <h2 className="text-sm font-bold text-text-primary">{title}</h2>
            <p className="text-xs font-medium leading-6 text-text-secondary">{subtitle}</p>
          </div>
        </div>

        <div className="shrink-0 rounded-full bg-white/5 px-3 py-2 text-xs font-bold text-accent">{actionLabel}</div>
      </div>
    </section>
  );

  return (
    <a href={href} target="_blank" rel="noreferrer">
      <div className="relative">
        {content}
        <div className="pointer-events-none absolute right-4 top-4 text-accent">
          <ArrowUpRight size={15} />
        </div>
      </div>
    </a>
  );
}
