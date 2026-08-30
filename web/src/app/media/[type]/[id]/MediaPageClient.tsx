"use client";

import React, { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { ArrowLeft, Bookmark, BookmarkCheck, Clock3, Film, Star } from "lucide-react";
import type { MediaItem, MediaType } from "@/lib/api";
import { FottyAPI } from "@/lib/api";
import { isFavorite, recordWatch, toggleFavorite } from "@/lib/storage";
import { EmptyState } from "@/components/EmptyState";
import { MediaCard } from "@/components/MediaCard";
import { ShimmerBlock } from "@/components/Skeleton";

export default function MediaDetailPage() {
  const params = useParams();
  const router = useRouter();
  const rawType = Array.isArray(params.type) ? params.type[0] : params.type;
  const rawId = Array.isArray(params.id) ? params.id[0] : params.id;
  const type = rawType === "tv" ? "tv" : "movie";
  const id = String(rawId || "");
  const [item, setItem] = useState<MediaItem | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [saved, setSaved] = useState(false);
  const [tracked, setTracked] = useState(false);

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      const detail = await FottyAPI.fetchMediaDetail(type as MediaType, id);
      if (!isMounted) return;
      setItem(detail);
      if (detail) setSaved(isFavorite(detail));
      setIsLoading(false);
    }

    load();
    return () => {
      isMounted = false;
    };
  }, [type, id]);

  if (isLoading) return <DetailSkeleton />;

  if (!item) {
    return (
      <main className="min-h-screen bg-background text-text-primary">
        <EmptyState icon={Film} title="Media not found" message="This title could not be loaded." actionLabel="Back" onAction={() => router.back()} />
      </main>
    );
  }

  const primaryMeta = [item.meta, item.year, item.runtime, item.status].filter(Boolean).join(" · ");

  return (
    <main className="min-h-screen bg-background pb-32 text-text-primary">
      <section className="relative min-h-[560px] overflow-hidden">
        <div className="absolute inset-0">
          {item.backdrop ? (
            <img src={item.backdrop} alt={item.title} className="h-full w-full object-cover" />
          ) : (
            <div className="h-full w-full bg-surface" />
          )}
          <div className="absolute inset-0 bg-gradient-to-b from-black/20 via-background/55 to-background" />
        </div>

        <div className="relative z-10 flex min-h-[560px] flex-col justify-between px-md pb-lg pt-12">
          <button
            onClick={() => router.back()}
            className="grid h-10 w-10 place-items-center rounded-full bg-black/45 text-white backdrop-blur"
            aria-label="Back"
          >
            <ArrowLeft size={18} />
          </button>

          <div className="flex items-end gap-4">
            <div className="hidden w-32 shrink-0 overflow-hidden rounded-lg border border-white/10 bg-white/5 shadow-xl sm:block">
              {item.poster ? (
                <img src={item.poster} alt={item.title} className="aspect-[2/3] h-full w-full object-cover" />
              ) : (
                <div className="grid aspect-[2/3] place-items-center text-text-tertiary">
                  <Film size={30} />
                </div>
              )}
            </div>

            <div className="min-w-0 flex-1 space-y-4">
              <div className="space-y-2">
                {item.tagline && <p className="text-xs font-semibold text-live">{item.tagline}</p>}
                <h1 className="max-w-[680px] text-4xl font-black leading-none text-white md:text-6xl">{item.title}</h1>
                {primaryMeta && <p className="text-sm font-medium text-text-secondary">{primaryMeta}</p>}
                {typeof item.rating === "number" && item.rating > 0 && (
                  <div className="flex items-center gap-2 text-sm font-bold text-live">
                    <Star size={15} className="fill-current" />
                    {item.rating.toFixed(1)}
                  </div>
                )}
              </div>

              <div className="flex flex-wrap gap-3">
                <button
                  onClick={() => {
                    recordWatch(item);
                    setTracked(true);
                  }}
                  className="flex h-12 min-w-32 items-center justify-center gap-2 rounded-full accent-gradient px-6 text-sm font-bold text-white transition-transform active:scale-95"
                >
                  <Clock3 size={16} />
                  {tracked ? "Added" : "Continue Later"}
                </button>
                <button
                  onClick={() => setSaved(toggleFavorite(item))}
                  className="flex h-12 items-center justify-center gap-2 rounded-full border border-white/10 bg-white/10 px-5 text-sm font-bold text-white backdrop-blur transition-colors hover:bg-white/15"
                >
                  {saved ? <BookmarkCheck size={17} /> : <Bookmark size={17} />}
                  {saved ? "Saved" : "Save"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <div className="space-y-xl px-md py-lg">
        {item.overview && (
          <section className="space-y-3">
            <h2 className="text-lg font-bold">Overview</h2>
            <p className="max-w-3xl text-sm leading-6 text-text-secondary">{item.overview}</p>
          </section>
        )}

        {item.genres && item.genres.length > 0 && (
          <section className="flex flex-wrap gap-2">
            {item.genres.map((genre) => (
              <span key={genre} className="rounded-full border border-white/10 bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary">
                {genre}
              </span>
            ))}
          </section>
        )}

        <section className="space-y-4">
          <h2 className="text-lg font-bold">Up Next</h2>
          <div className="no-scrollbar flex gap-md overflow-x-auto">
            <MediaCard item={item} />
          </div>
        </section>
      </div>
    </main>
  );
}

function DetailSkeleton() {
  return (
    <main className="min-h-screen bg-background pb-32">
      <ShimmerBlock className="h-[560px] w-full rounded-none" />
      <div className="space-y-4 px-md py-lg">
        <ShimmerBlock className="h-8 w-48" />
        <ShimmerBlock className="h-24 w-full" />
      </div>
    </main>
  );
}
