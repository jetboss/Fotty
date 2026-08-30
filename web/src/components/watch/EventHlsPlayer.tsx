"use client";

import React, { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from "react";
import Hls from "hls.js";
import { resolveFottyApiUrl } from "@/lib/fotty-api-fetch";

export type EventHlsPlayerHandle = {
  unmute: () => void;
};

function proxiedMediaUrl(absoluteUrl: string, watchToken?: string) {
  const params = new URLSearchParams({ url: absoluteUrl });
  if (watchToken) params.set("watchToken", watchToken);
  return resolveFottyApiUrl(`/api/embed/hls?${params.toString()}`);
}

function liveHlsConfig(): Partial<Hls["config"]> {
  return {
    enableWorker: true,
    lowLatencyMode: true,
    backBufferLength: 0,
    maxBufferLength: 12,
    maxMaxBufferLength: 20,
    liveSyncDurationCount: 2,
    liveMaxLatencyDurationCount: 5,
    startFragPrefetch: true,
  };
}

export const EventHlsPlayer = forwardRef<
  EventHlsPlayerHandle,
  {
    manifestUrl: string;
    watchToken?: string;
    title: string;
    onPlaybackStarted?: () => void;
    onPlaybackError?: (message: string) => void;
  }
>(function EventHlsPlayer({ manifestUrl, watchToken, title, onPlaybackStarted, onPlaybackError }, ref) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const startedRef = useRef(false);
  const [needsUnmute, setNeedsUnmute] = useState(false);
  const [failed, setFailed] = useState(false);

  const unmute = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    video.muted = false;
    setNeedsUnmute(false);
    void video.play().catch(() => {});
  }, []);

  useImperativeHandle(ref, () => ({ unmute }), [unmute]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !manifestUrl) return;

    startedRef.current = false;
    setNeedsUnmute(false);
    setFailed(false);

    const playbackSrc = proxiedMediaUrl(manifestUrl, watchToken);
    let cancelled = false;

    function reportFailure() {
      if (cancelled) return;
      setFailed(true);
      onPlaybackError?.("This stream had trouble starting. Fotty will try another path.");
    }

    function markStarted() {
      if (startedRef.current || cancelled) return;
      startedRef.current = true;
      onPlaybackStarted?.();
    }

    function handleAutoplayBlocked(target: HTMLVideoElement) {
      target.muted = true;
      setNeedsUnmute(true);
      void target.play().catch(() => {});
    }

    if (Hls.isSupported()) {
      const hls = new Hls(liveHlsConfig());
      hlsRef.current = hls;

      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        if (cancelled) return;
        video.muted = true;
        const playPromise = video.play();
        if (playPromise) {
          playPromise
            .then(() => {
              markStarted();
              if (video.muted) setNeedsUnmute(true);
            })
            .catch(() => {
              handleAutoplayBlocked(video);
              markStarted();
            });
        }
      });

      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (cancelled || !data.fatal) return;
        reportFailure();
      });

      hls.loadSource(playbackSrc);
      hls.attachMedia(video);

      return () => {
        cancelled = true;
        hls.destroy();
        hlsRef.current = null;
      };
    }

    if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = playbackSrc;
      video.muted = true;
      const onPlaying = () => markStarted();
      const onVideoError = () => reportFailure();
      video.addEventListener("playing", onPlaying);
      video.addEventListener("error", onVideoError);
      void video.play()
        .then(() => {
          markStarted();
          if (video.muted) setNeedsUnmute(true);
        })
        .catch(() => {
          handleAutoplayBlocked(video);
          markStarted();
        });

      return () => {
        cancelled = true;
        video.removeEventListener("playing", onPlaying);
        video.removeEventListener("error", onVideoError);
        video.removeAttribute("src");
        video.load();
      };
    }

    reportFailure();
    return undefined;
  }, [manifestUrl, onPlaybackError, onPlaybackStarted, watchToken]);

  return (
    <div className="absolute inset-0 bg-black">
      {failed ? (
        <div className="absolute inset-0 grid place-items-center bg-black px-6 text-center text-sm font-medium text-white/60">
          Switching to backup player…
        </div>
      ) : (
        <video
          ref={videoRef}
          className="h-full w-full bg-black object-contain"
          playsInline
          autoPlay
          muted
          title={title}
        />
      )}
      {needsUnmute ? (
        <button
          type="button"
          onClick={unmute}
          className="absolute inset-0 z-10 flex items-center justify-center bg-black/35 text-sm font-black uppercase tracking-wide text-white"
        >
          Tap to unmute
        </button>
      ) : null}
    </div>
  );
});
