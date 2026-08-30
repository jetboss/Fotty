"use client";

import { useEffect, useMemo, useState } from "react";
import { Newspaper } from "lucide-react";
import { buildHeadlinesFeed } from "@/lib/football-personalization";
import type { TrackedTeamEntry } from "@/lib/storage";

interface HeadlineItem {
  id: string;
  title: string;
  url: string;
  source?: string;
}

interface HomeHeadlinesPanelProps {
  trackedTeams?: TrackedTeamEntry[];
  limit?: number;
}

const HEADLINES_CACHE_MS = 5 * 60 * 1000;
const headlinesCache = new Map<string, { fetchedAt: number; headlines: HeadlineItem[]; error: string | null }>();

export function HomeHeadlinesPanel({ trackedTeams = [], limit = 5 }: HomeHeadlinesPanelProps) {
  const feed = useMemo(() => buildHeadlinesFeed(trackedTeams), [trackedTeams]);
  const cacheKey = `${feed.query}:${limit}`;
  const cached = headlinesCache.get(cacheKey);
  const [headlines, setHeadlines] = useState<HeadlineItem[]>(() => cached?.headlines ?? []);
  const [loading, setLoading] = useState(() => !cached);
  const [error, setError] = useState<string | null>(() => cached?.error ?? null);

  useEffect(() => {
    let cancelled = false;
    const hit = headlinesCache.get(cacheKey);
    if (hit && Date.now() - hit.fetchedAt < HEADLINES_CACHE_MS) {
      setHeadlines(hit.headlines);
      setError(hit.error);
      setLoading(false);
      return;
    }

    setLoading(true);

    fetch(`/api/football/headlines?q=${encodeURIComponent(feed.query)}&limit=${limit}`)
      .then((res) => res.json())
      .then((data: { headlines?: HeadlineItem[]; error?: string }) => {
        if (cancelled) return;
        const nextHeadlines = data.headlines ?? [];
        const nextError = data.error ?? null;
        headlinesCache.set(cacheKey, {
          fetchedAt: Date.now(),
          headlines: nextHeadlines,
          error: nextError,
        });
        setHeadlines(nextHeadlines);
        setError(nextError);
      })
      .catch(() => {
        if (!cancelled) setError("Could not load headlines");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [cacheKey, feed.query, limit]);

  return (
    <section className="rounded-xl border border-white/5 bg-surface p-4">
      <div className="mb-3 flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <Newspaper size={16} className="shrink-0 text-accent" />
            <h2 className="text-xs font-black uppercase tracking-wide text-text-primary">Latest headlines</h2>
          </div>
          <p className="mt-1 text-[10px] font-medium text-text-tertiary">
            {trackedTeams.length > 0 ? feed.label : "Premier League"}
            {trackedTeams.length > 0 ? " · from teams you follow" : ""}
          </p>
        </div>
      </div>

      {loading ? (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-12 animate-pulse rounded-lg bg-white/5" />
          ))}
        </div>
      ) : headlines.length === 0 ? (
        <p className="text-xs font-medium leading-5 text-text-secondary">
          {error || "No headlines right now. Check back shortly."}
        </p>
      ) : (
        <ul className="space-y-3">
          {headlines.map((item) => (
            <li key={item.id}>
              <a
                href={item.url}
                target="_blank"
                rel="noopener noreferrer"
                className="group block rounded-lg border border-transparent px-1 py-1 transition-colors hover:border-white/5 hover:bg-white/[0.03]"
              >
                <p className="line-clamp-2 text-xs font-semibold leading-5 text-text-primary group-hover:text-white">
                  {item.title}
                </p>
                {item.source && (
                  <p className="mt-1 text-[10px] font-medium text-text-tertiary">{item.source}</p>
                )}
              </a>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
