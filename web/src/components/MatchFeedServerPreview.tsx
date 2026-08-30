import Link from "next/link";
import type { ScrapedMatch } from "@/lib/api";
import { buildServerWatchHref, serverMatchKey } from "@/lib/server/watch-link";
import { serverStatusLabel } from "@/lib/server/match-labels";

interface MatchFeedServerPreviewProps {
  matches: ScrapedMatch[];
  returnTo: string;
  title?: string;
  subtitle?: string;
  limit?: number;
}

export function MatchFeedServerPreview({
  matches,
  returnTo,
  title = "Live fixtures",
  subtitle = "Open a match from the Fotty live board",
  limit = 8,
}: MatchFeedServerPreviewProps) {
  const items = matches.slice(0, limit);
  if (items.length === 0) return null;

  return (
    <section className="px-md pb-4" data-server-feed>
      <FeedPreviewBody title={title} subtitle={subtitle} items={items} returnTo={returnTo} />
    </section>
  );
}

function FeedPreviewBody({
  title,
  subtitle,
  items,
  returnTo,
}: {
  title: string;
  subtitle: string;
  items: ScrapedMatch[];
  returnTo: string;
}) {
  return (
    <div className="mx-auto max-w-5xl space-y-3">
      <div className="space-y-1">
        <h2 className="text-sm font-black text-text-primary">{title}</h2>
        <p className="text-xs font-medium text-text-secondary">{subtitle}</p>
      </div>
      <ul className="grid gap-2 sm:grid-cols-2">
        {items.map((match) => {
          const cardTitle = match.displayTitle || match.title;
          const href = buildServerWatchHref(match, returnTo);
          const isFixture = match.kind === "fixture" && Boolean(match.teams);
          const status = serverStatusLabel(match);

          return (
            <li key={serverMatchKey(match)}>
              <Link
                href={href}
                className="block rounded-lg border border-white/5 bg-surface px-4 py-3 transition-colors hover:bg-surface-elevated"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 space-y-1">
                    <p className="truncate text-[11px] font-black uppercase text-text-tertiary">
                      {match.league || match.sport || "Live Sports"}
                    </p>
                    {isFixture && match.teams ? (
                      <p className="text-sm font-bold text-text-primary">
                        {match.teams.home.name} vs {match.teams.away.name}
                      </p>
                    ) : (
                      <p className="truncate text-sm font-bold text-text-primary">{cardTitle}</p>
                    )}
                  </div>
                  {status ? (
                    <span className="shrink-0 rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-[10px] font-black uppercase text-text-secondary">
                      {status}
                    </span>
                  ) : null}
                </div>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
