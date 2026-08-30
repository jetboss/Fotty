"use client";

import React, { useCallback, useEffect, useRef, useState } from "react";
import Hls from "hls.js";
import { LoaderCircle, Maximize, Minimize, Pause, Play, Radio, Volume2, VolumeX } from "lucide-react";
import { p2pHlsConfig, resolveP2PDeliverySetup } from "@/lib/p2p-media-delivery";
import { logStreamDiagnostic } from "@/lib/stream-guide/diagnostics";
import { cn } from "@/lib/utils";
import { getWatchAuthHeaders } from "@/lib/watch-auth-headers";
import { fetchFottyApi, getPublicFottyApiBase } from "@/lib/fotty-api-fetch";
import { invalidateWatchSessionToken, isWatchSessionAuthError, refreshWatchSessionIfNeeded } from "@/lib/watch-session";
import {
  isDecodedProgressSample,
  shouldRecoverStalledPlayback,
} from "@/lib/playback-controller";

const MAX_FATAL_RETRIES = 2;
const STALL_OVERLAY_MS = 4000;
const MIN_BUFFER_BEFORE_PLAY_SEC = 5;
const LIVE_EDGE_DRIFT_SEC = 45;
const WATCHDOG_INTERVAL_MS = 2500;
const PLAYHEAD_STALL_MS = 14000;
const HARD_STALL_MS = 35000;
const LOW_BUFFER_RECOVERY_SEC = 6;
const MAX_SOFT_STALL_RECOVERIES = 2;
const SOFT_RECOVERY_COOLDOWN_MS = 8_000;
const MAX_VIDEO_ELEMENT_STARTUP_RECOVERIES = 1;
const MAX_VIDEO_ELEMENT_LIVE_RECOVERIES = 3;
const VIDEO_ELEMENT_RECOVERY_DELAY_MS = 2000;
const VIDEO_ELEMENT_RECOVERY_RESET_MS = 60000;
const STARTUP_DECODE_TIMEOUT_MS = 45_000;

function bufferedAheadSeconds(video: HTMLVideoElement): number {
  const ranges = video.buffered;
  if (!ranges.length) return 0;
  const current = video.currentTime;
  for (let index = 0; index < ranges.length; index += 1) {
    const start = ranges.start(index);
    const end = ranges.end(index);
    if (current >= start && current <= end) {
      return Math.max(0, end - current);
    }
  }
  return Math.max(0, ranges.end(ranges.length - 1) - current);
}

function nativeLiveEdgeSeconds(video: HTMLVideoElement): number | null {
  const ranges = video.seekable;
  if (!ranges.length) return null;
  const liveEdge = ranges.end(ranges.length - 1);
  return Number.isFinite(liveEdge) ? liveEdge : null;
}

function streamURLWithRecoveryNonce(source: string, nonce: number): string {
  const url = new URL(source, window.location.origin);
  url.searchParams.set("_fottyRecovery", `${Date.now()}-${nonce}`);
  return url.origin === window.location.origin ? `${url.pathname}${url.search}` : url.toString();
}

interface VideoPlayerProps {
  src: string;
  title: string;
  poster?: string;
  playbackKey?: string | number;
  onStall?: () => void;
  onRecover?: () => void;
  onPlaybackStarted?: () => void;
  onPlaybackFailure?: (message: string, reason: string) => void;
  onRetry?: () => void;
}

export const VideoPlayer: React.FC<VideoPlayerProps> = ({
  src,
  title,
  poster,
  playbackKey = 0,
  onStall,
  onRecover,
  onPlaybackStarted,
  onPlaybackFailure,
  onRetry,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const fatalRetryCountRef = useRef(0);
  const hasStartedRef = useRef(false);
  const isPlayingRef = useRef(false);
  const lastProgressAtRef = useRef(0);
  const lastCurrentTimeRef = useRef(0);
  const softStallRecoveryCountRef = useRef(0);
  const lastSoftRecoveryAtRef = useRef(0);
  const videoElementRecoveryCountRef = useRef(0);
  const lastVideoElementErrorAtRef = useRef(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [showTopChrome, setShowTopChrome] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isBuffering, setIsBuffering] = useState(false);
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const chromeTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [streamSrc, setStreamSrc] = useState<string | null>(null);
  const [deliveryMode, setDeliveryMode] = useState<"plain-hls" | "webrtc-hls" | "webrtc-fallback">("plain-hls");
  const [hasPlaybackStarted, setHasPlaybackStarted] = useState(false);
  const [needsUnmute, setNeedsUnmute] = useState(false);
  const [retryNonce, setRetryNonce] = useState(0);
  const autoplayAttemptedRef = useRef(false);
  const stallOverlayTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const liveRecoveryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const videoElementRecoveryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onStallRef = useRef(onStall);
  const onRecoverRef = useRef(onRecover);
  const onPlaybackStartedRef = useRef(onPlaybackStarted);
  const onPlaybackFailureRef = useRef(onPlaybackFailure);
  const onRetryRef = useRef(onRetry);
  const playbackErrorRef = useRef(playbackError);

  useEffect(() => {
    onStallRef.current = onStall;
    onRecoverRef.current = onRecover;
    onPlaybackStartedRef.current = onPlaybackStarted;
    onPlaybackFailureRef.current = onPlaybackFailure;
    onRetryRef.current = onRetry;
  }, [onStall, onRecover, onPlaybackStarted, onPlaybackFailure, onRetry]);

  useEffect(() => {
    playbackErrorRef.current = playbackError;
  }, [playbackError]);

  useEffect(() => {
    isPlayingRef.current = isPlaying;
  }, [isPlaying]);

  const reportFailure = useCallback(
    (message: string, reason: string) => {
      if (isWatchSessionAuthError(message)) {
        void refreshWatchSessionIfNeeded().then((refreshed) => {
          if (!refreshed) invalidateWatchSessionToken();
        });
      }
      setPlaybackError(message);
      setIsBuffering(false);
      logStreamDiagnostic("playback_start_failure", { reason, playbackMode: "p2p" });
      onPlaybackFailureRef.current?.(message, reason);
    },
    []
  );

  useEffect(() => {
    let cancelled = false;
    setStreamSrc(null);

    async function resolveStreamSource() {
      const url = new URL(src, window.location.origin);
      const isSameOrigin = url.origin === window.location.origin;
      const getStreamURL = () => isSameOrigin ? `${url.pathname}${url.search}` : url.toString();
      const headers = getWatchAuthHeaders();

      if (!headers["X-Fotty-Email"]) {
        return { streamURL: getStreamURL() };
      }

      try {
        const tokenResponse = await fetchFottyApi("/api/stream/token", {
          headers: { Accept: "application/json", ...headers },
          cache: "no-store",
        });

        if (tokenResponse.status === 401) {
          if (await refreshWatchSessionIfNeeded()) {
            const retry = await fetchFottyApi("/api/stream/token", {
              headers: { Accept: "application/json", ...getWatchAuthHeaders() },
              cache: "no-store",
            });
            if (retry.ok) {
              const data = (await retry.json()) as { watchToken?: string };
              if (data.watchToken) {
                url.searchParams.set("watchToken", data.watchToken);
                return { streamURL: getStreamURL() };
              }
            }
          }
          return { error: "Your session expired. Sign in again to watch." };
        }
        if (tokenResponse.status === 403) {
          return { error: "A paid Fotty plan is required to watch this stream." };
        }

        if (tokenResponse.ok) {
          const data = (await tokenResponse.json()) as { watchToken?: string };
          if (data.watchToken) {
            url.searchParams.set("watchToken", data.watchToken);
            return { streamURL: getStreamURL() };
          }
          return { error: "Stream authorization is not configured. Try again later." };
        }

        const probeHeaders: Record<string, string> = {
          Accept: "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*",
        };
        if (isSameOrigin) {
          Object.assign(probeHeaders, headers);
        }

        const probe = await fetch(url.toString(), {
          headers: probeHeaders,
          cache: "no-store",
        });

        if (probe.ok) {
          return { streamURL: getStreamURL() };
        }
        if (probe.status === 401) {
          return { error: "Your session expired. Sign in again to watch." };
        }
        if (probe.status === 403) {
          return { error: "A paid Fotty plan is required to watch this stream." };
        }

        return { error: "Playback could not start from this source." };
      } catch {
        logStreamDiagnostic("manifest_load_failure", { reason: "stream_token", playbackMode: "p2p" });
        return { error: "Could not reach the stream service. Check your connection and try again." };
      }
    }

    void resolveStreamSource().then((result) => {
      if (cancelled) return;
      if (result.error) {
        reportFailure(result.error, "stream_auth");
        return;
      }
      setPlaybackError(null);
      setStreamSrc(result.streamURL || src);
    });

    return () => {
      cancelled = true;
    };
  }, [reportFailure, src, playbackKey, retryNonce]);

  const attemptAutoplay = useCallback(async () => {
    const video = videoRef.current;
    if (!video || autoplayAttemptedRef.current) return;

    autoplayAttemptedRef.current = true;
    video.muted = false;
    setIsMuted(false);

    try {
      await video.play();
      setIsPlaying(true);
      setNeedsUnmute(false);
      return;
    } catch {
      // Browser blocked unmuted autoplay — fall back to muted start.
    }

    video.muted = true;
    setIsMuted(true);
    try {
      await video.play();
      setIsPlaying(true);
      setNeedsUnmute(true);
    } catch {
      autoplayAttemptedRef.current = false;
      setIsPlaying(false);
    }
  }, []);

  useEffect(() => {
    autoplayAttemptedRef.current = false;
    hasStartedRef.current = false;
    fatalRetryCountRef.current = 0;
    softStallRecoveryCountRef.current = 0;
    lastSoftRecoveryAtRef.current = 0;
    videoElementRecoveryCountRef.current = 0;
    lastVideoElementErrorAtRef.current = 0;
    lastProgressAtRef.current = Date.now();
    lastCurrentTimeRef.current = 0;
    if (videoElementRecoveryTimerRef.current) {
      clearTimeout(videoElementRecoveryTimerRef.current);
      videoElementRecoveryTimerRef.current = null;
    }
    setHasPlaybackStarted(false);
    setNeedsUnmute(false);
    setPlaybackError(null);
  }, [streamSrc, playbackKey]);

  const recoverFromVideoElementError = useCallback(
    (reason: string) => {
      const video = videoRef.current;
      if (!video || !streamSrc || playbackErrorRef.current) return false;

      if (videoElementRecoveryTimerRef.current) {
        setPlaybackError(null);
        setIsBuffering(true);
        return true;
      }

      const now = Date.now();
      if (now - lastVideoElementErrorAtRef.current > VIDEO_ELEMENT_RECOVERY_RESET_MS) {
        videoElementRecoveryCountRef.current = 0;
      }
      lastVideoElementErrorAtRef.current = now;

      const recoveryLimit = hasStartedRef.current
        ? MAX_VIDEO_ELEMENT_LIVE_RECOVERIES
        : MAX_VIDEO_ELEMENT_STARTUP_RECOVERIES;
      if (videoElementRecoveryCountRef.current >= recoveryLimit) {
        return false;
      }

      videoElementRecoveryCountRef.current += 1;
      autoplayAttemptedRef.current = false;
      lastProgressAtRef.current = Date.now();
      setPlaybackError(null);
      setIsBuffering(true);
      onStallRef.current?.();

      const hls = hlsRef.current;
      if (hls) {
        const liveSyncPosition = hls.liveSyncPosition;
        if (
          typeof liveSyncPosition === "number" &&
          Number.isFinite(liveSyncPosition) &&
          (video.currentTime <= 0 || video.currentTime < liveSyncPosition - LIVE_EDGE_DRIFT_SEC)
        ) {
          video.currentTime = liveSyncPosition;
        }

        try {
          hls.recoverMediaError();
        } catch {
          // Some browser/media states reject media recovery; restarting loading is still useful.
        }

        try {
          hls.startLoad(typeof liveSyncPosition === "number" ? liveSyncPosition : undefined);
        } catch {
          try {
            hls.startLoad();
          } catch {
            // Let the next watchdog or media event try again.
          }
        }
      } else {
        video.pause();
        video.src = streamURLWithRecoveryNonce(streamSrc, videoElementRecoveryCountRef.current);
        video.load();
      }

      logStreamDiagnostic("playback_stalled", {
        reason: `${reason}_video_recovery_${videoElementRecoveryCountRef.current}`,
        playbackMode: "p2p",
      });

      const backoffDelay = Math.min(
        15000,
        VIDEO_ELEMENT_RECOVERY_DELAY_MS * Math.pow(1.5, videoElementRecoveryCountRef.current - 1)
      );

      videoElementRecoveryTimerRef.current = setTimeout(() => {
        videoElementRecoveryTimerRef.current = null;
        if (!videoRef.current || playbackErrorRef.current) return;
        void attemptAutoplay();
      }, backoffDelay);

      return true;
    },
    [attemptAutoplay, streamSrc]
  );

  useEffect(() => {
    const video = videoRef.current;
    if (!streamSrc || !video) return;

    let cancelled = false;
    setPlaybackError(null);

    const onCanPlay = () => {
      if (bufferedAheadSeconds(video) >= MIN_BUFFER_BEFORE_PLAY_SEC) {
        void attemptAutoplay();
      }
    };
    const recoverLivePlayback = (reason: string) => {
      const hls = hlsRef.current;
      if (!hls || playbackErrorRef.current) return;

      const liveSyncPosition = hls.liveSyncPosition;
      const shouldJumpToLive =
        typeof liveSyncPosition === "number" &&
        Number.isFinite(liveSyncPosition) &&
        (video.currentTime <= 0 || video.currentTime < liveSyncPosition - LIVE_EDGE_DRIFT_SEC);

      if (shouldJumpToLive) {
        video.currentTime = liveSyncPosition;
      }

      try {
        hls.startLoad(shouldJumpToLive && typeof liveSyncPosition === "number" ? liveSyncPosition : undefined);
      } catch {
        hls.startLoad();
      }

      logStreamDiagnostic("playback_stalled", { reason, playbackMode: "p2p" });
    };
    const markDecodedPlaybackStarted = () => {
      if (hasStartedRef.current) return;
      hasStartedRef.current = true;
      setHasPlaybackStarted(true);
      setIsBuffering(false);
      setPlaybackError(null);
      logStreamDiagnostic("playback_start_success", {
        reason: "decoded_progress",
        playbackMode: "p2p",
      });
      onPlaybackStartedRef.current?.();
    };
    const notePlaybackProgress = () => {
      const previousTime = lastCurrentTimeRef.current;
      if (video.currentTime > previousTime + 0.2) {
        lastCurrentTimeRef.current = video.currentTime;
        lastProgressAtRef.current = Date.now();
        softStallRecoveryCountRef.current = 0;
        lastSoftRecoveryAtRef.current = 0;
        if (isDecodedProgressSample({
          previousTime,
          currentTime: video.currentTime,
          readyState: video.readyState,
          videoWidth: video.videoWidth,
        })) {
          markDecodedPlaybackStarted();
        }
      }
    };
    video.addEventListener("canplay", onCanPlay);
    video.addEventListener("timeupdate", notePlaybackProgress);
    video.addEventListener("progress", notePlaybackProgress);
    const startupDecodeTimer = window.setTimeout(() => {
      if (playbackErrorRef.current) return;
      const currentVideo = videoRef.current;
      if (!currentVideo) return;
      if (hasStartedRef.current) return;

      reportFailure("Playback is still buffering. Reconnecting this source.", "startup_decode_timeout");
    }, STARTUP_DECODE_TIMEOUT_MS);

    if (Hls.isSupported()) {
      void resolveP2PDeliverySetup(Hls, streamSrc).then((delivery) => {
        if (cancelled) return;
        setDeliveryMode(delivery.mode);
        const HlsConstructor = delivery.HlsConstructor;
        const hls = new HlsConstructor({
        capLevelToPlayerSize: true,
        enableWorker: true,
        startLevel: -1,
        startFragPrefetch: true,
        lowLatencyMode: false,
        // Buffered live sync (native-player style): keep distance from the live edge when Ace segments arrive unevenly.
        liveSyncMode: "buffered",
        liveSyncDurationCount: 6,
        liveMaxLatencyDurationCount: 18,
        maxLiveSyncPlaybackRate: 1.0,
        maxBufferLength: 90,
        maxMaxBufferLength: 180,
        maxBufferHole: 4.0,
        highBufferWatchdogPeriod: 4,
        nudgeMaxRetry: 8,
        backBufferLength: 60,
        debug: false,
        manifestLoadingTimeOut: 60_000,
        manifestLoadingMaxRetry: 8,
        manifestLoadingRetryDelay: 1000,
        fragLoadingTimeOut: 120_000,
        fragLoadingMaxRetry: 10,
        fragLoadingRetryDelay: 1000,
        appendErrorMaxRetry: 6,
        xhrSetup: (xhr, url) => {
          try {
            const target = new URL(url, window.location.origin);
            const apiBase = getPublicFottyApiBase();
            const fottyApiOrigin = apiBase ? new URL(apiBase).origin : "";
            const allowAuthHeaders =
              target.origin === window.location.origin ||
              (Boolean(fottyApiOrigin) && target.origin === fottyApiOrigin);
            if (!allowAuthHeaders) {
              return;
            }
            if (
              target.searchParams.has("watchToken") ||
              target.pathname === "/api/stream/native" ||
              target.pathname === "/api/stream/native/"
            ) {
              return;
            }
          } catch {
            return;
          }
          for (const [key, value] of Object.entries(getWatchAuthHeaders())) {
            xhr.setRequestHeader(key, value);
          }
        },
        ...p2pHlsConfig(delivery.mode === "webrtc-hls" ? delivery.swarmId : undefined),
      } as ConstructorParameters<typeof Hls>[0] & Record<string, unknown>);
      hlsRef.current = hls;
      hls.loadSource(streamSrc);
      hls.attachMedia(video);

      const clearBufferingOverlay = () => {
        setIsBuffering(false);
      };

      const maybeStartPlayback = () => {
        if (hasStartedRef.current) return;
        const ahead = bufferedAheadSeconds(video);
        if (ahead >= MIN_BUFFER_BEFORE_PLAY_SEC) {
          void attemptAutoplay();
        }
      };

      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        setPlaybackError(null);
        clearBufferingOverlay();
        if (hasStartedRef.current) {
          fatalRetryCountRef.current = 0;
        }
      });

      hls.on(Hls.Events.FRAG_LOADING, clearBufferingOverlay);
      hls.on(Hls.Events.FRAG_BUFFERED, () => {
        maybeStartPlayback();
      });
      hls.on(Hls.Events.BUFFER_APPENDED, maybeStartPlayback);

      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (!data.fatal) {
          if (
            data.details === Hls.ErrorDetails.BUFFER_STALLED_ERROR ||
            data.details === Hls.ErrorDetails.BUFFER_SEEK_OVER_HOLE
          ) {
            recoverLivePlayback(String(data.details));
          }
          return;
        }

        const httpStatus =
          data.response && typeof data.response === "object" && "code" in data.response
            ? Number((data.response as { code?: number }).code)
            : undefined;

        if (httpStatus === 401) {
          reportFailure("Your session expired. Sign in again to watch.", "manifest_401");
          hls.destroy();
          hlsRef.current = null;
          return;
        }
        if (httpStatus === 403) {
          reportFailure("A paid Fotty plan is required to watch this stream.", "manifest_403");
          hls.destroy();
          hlsRef.current = null;
          return;
        }

        switch (data.type) {
          case Hls.ErrorTypes.NETWORK_ERROR:
            if (fatalRetryCountRef.current < MAX_FATAL_RETRIES) {
              fatalRetryCountRef.current += 1;
              setPlaybackError(null);
              logStreamDiagnostic("playback_stalled", { reason: "network", playbackMode: "p2p" });
              recoverLivePlayback("network");
              return;
            }
            reportFailure("Playback could not start from this source.", "network_fatal");
            hls.destroy();
            hlsRef.current = null;
            break;
          case Hls.ErrorTypes.MEDIA_ERROR:
            if (fatalRetryCountRef.current < MAX_FATAL_RETRIES) {
              fatalRetryCountRef.current += 1;
              setPlaybackError(null);
              logStreamDiagnostic("playback_stalled", { reason: "media", playbackMode: "p2p" });
              hls.recoverMediaError();
              return;
            }
            reportFailure("Playback could not start from this source.", "media_fatal");
            hls.destroy();
            hlsRef.current = null;
            break;
          default:
            reportFailure("Playback could not start from this source.", `fatal_${data.type}`);
            logStreamDiagnostic("manifest_load_failure", {
              reason: String(data.details),
              playbackMode: "p2p",
            });
            hls.destroy();
            hlsRef.current = null;
            break;
        }
      });

      });
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      setDeliveryMode("plain-hls");
      video.src = streamSrc;
    }

    const playbackWatchdog = window.setInterval(() => {
      if (!hasStartedRef.current || !isPlayingRef.current || playbackErrorRef.current) return;

      const previousTime = lastCurrentTimeRef.current;
      notePlaybackProgress();
      if (lastCurrentTimeRef.current > previousTime) return;

      if (video.paused) {
        void video.play().catch(() => undefined);
      }

      const stalledMs = Date.now() - lastProgressAtRef.current;
      if (!shouldRecoverStalledPlayback({
        hasStarted: hasStartedRef.current,
        isPlaying: isPlayingRef.current,
        hasError: Boolean(playbackErrorRef.current),
        stalledMs,
        playheadStallMs: PLAYHEAD_STALL_MS,
        hardStallMs: HARD_STALL_MS,
        bufferAhead: bufferedAheadSeconds(video),
        lowBufferSeconds: LOW_BUFFER_RECOVERY_SEC,
        readyState: video.readyState,
      })) {
        return;
      }

      const now = Date.now();
      if (now - lastSoftRecoveryAtRef.current < SOFT_RECOVERY_COOLDOWN_MS) return;
      lastSoftRecoveryAtRef.current = now;
      softStallRecoveryCountRef.current += 1;

      const hls = hlsRef.current;
      const hardRecovery =
        stalledMs >= HARD_STALL_MS ||
        softStallRecoveryCountRef.current > MAX_SOFT_STALL_RECOVERIES;
      if (!hardRecovery) {
        setIsBuffering(true);
        onStallRef.current?.();

        if (hls) {
          const liveSyncPosition = hls.liveSyncPosition;
          if (
            typeof liveSyncPosition === "number" &&
            Number.isFinite(liveSyncPosition) &&
            (video.currentTime <= 0 ||
              video.currentTime < liveSyncPosition - LIVE_EDGE_DRIFT_SEC)
          ) {
            video.currentTime = liveSyncPosition;
          }
          try {
            hls.startLoad(
              typeof liveSyncPosition === "number" ? liveSyncPosition : undefined
            );
          } catch {
            hls.startLoad();
          }
        } else {
          const liveEdge = nativeLiveEdgeSeconds(video);
          if (
            liveEdge !== null &&
            (video.currentTime <= 0 ||
              video.currentTime < liveEdge - LIVE_EDGE_DRIFT_SEC)
          ) {
            video.currentTime = liveEdge;
          }
          void video.play().catch(() => undefined);
        }

        logStreamDiagnostic("playback_stalled", {
          reason: hls ? "hls_watchdog_soft" : "safari_watchdog_soft",
          playbackMode: "p2p",
        });
        return;
      }

      const reason = hls ? "hls_watchdog_hard" : "safari_watchdog_hard";
      if (!recoverFromVideoElementError(reason)) {
        reportFailure("Playback stopped making progress from this source.", reason);
      }
    }, WATCHDOG_INTERVAL_MS);

    if ("mediaSession" in navigator && typeof MediaMetadata !== "undefined") {
      try {
        navigator.mediaSession.metadata = new MediaMetadata({
          title,
          artist: "Fotty Live",
          album: "Match Center",
          artwork: [
            { src: "/icon-192.png", sizes: "192x192", type: "image/png" },
            { src: "/icon-512.png", sizes: "512x512", type: "image/png" },
          ],
        });

        navigator.mediaSession.setActionHandler("play", () => video.play());
        navigator.mediaSession.setActionHandler("pause", () => video.pause());
      } catch {
        // Media Session support varies by desktop browser; playback must continue without it.
      }
    }

    return () => {
      cancelled = true;
      video.removeEventListener("canplay", onCanPlay);
      video.removeEventListener("timeupdate", notePlaybackProgress);
      video.removeEventListener("progress", notePlaybackProgress);
      window.clearTimeout(startupDecodeTimer);
      window.clearInterval(playbackWatchdog);
      if (stallOverlayTimerRef.current) clearTimeout(stallOverlayTimerRef.current);
      if (liveRecoveryTimerRef.current) clearTimeout(liveRecoveryTimerRef.current);
      if (videoElementRecoveryTimerRef.current) {
        clearTimeout(videoElementRecoveryTimerRef.current);
        videoElementRecoveryTimerRef.current = null;
      }
      video.pause();
      video.removeAttribute("src");
      video.load();
      if (chromeTimeoutRef.current) clearTimeout(chromeTimeoutRef.current);
      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }
    };
  }, [attemptAutoplay, playbackKey, recoverFromVideoElementError, reportFailure, streamSrc, title]);

  useEffect(() => {
    const handleFullscreenChange = () => {
      const root = containerRef.current;
      const doc = document as Document & { webkitFullscreenElement?: Element };
      const active = document.fullscreenElement === root || doc.webkitFullscreenElement === root;
      setIsFullscreen(active);
      if (active) setShowTopChrome(true);
    };

    document.addEventListener("fullscreenchange", handleFullscreenChange);
    document.addEventListener("webkitfullscreenchange", handleFullscreenChange);
    return () => {
      document.removeEventListener("fullscreenchange", handleFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", handleFullscreenChange);
    };
  }, []);

  const togglePlay = () => {
    if (!videoRef.current) return;
    if (isPlaying) {
      videoRef.current.pause();
      setIsPlaying(false);
      return;
    }
    videoRef.current.play().then(() => setIsPlaying(true)).catch(() => setIsPlaying(false));
  };

  const toggleMute = () => {
    if (!videoRef.current) return;
    const nextMuted = !isMuted;
    videoRef.current.muted = nextMuted;
    setIsMuted(nextMuted);
    if (!nextMuted) setNeedsUnmute(false);
  };

  const retryPlayback = () => {
    onRetryRef.current?.();
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
    fatalRetryCountRef.current = 0;
    videoElementRecoveryCountRef.current = 0;
    lastVideoElementErrorAtRef.current = 0;
    if (videoElementRecoveryTimerRef.current) {
      clearTimeout(videoElementRecoveryTimerRef.current);
      videoElementRecoveryTimerRef.current = null;
    }
    autoplayAttemptedRef.current = false;
    hasStartedRef.current = false;
    setHasPlaybackStarted(false);
    setIsBuffering(false);
    setPlaybackError(null);
    setStreamSrc(null);
    setRetryNonce((value) => value + 1);
  };

  const revealTopChrome = (autoHide = true) => {
    setShowTopChrome(true);
    if (chromeTimeoutRef.current) clearTimeout(chromeTimeoutRef.current);
    if (!autoHide || isFullscreen) return;
    chromeTimeoutRef.current = setTimeout(() => setShowTopChrome(false), 4000);
  };

  const openFullscreen = async () => {
    const container = containerRef.current;
    const video = videoRef.current;
    if (!container || !video) return;

    const doc = document as Document & { webkitFullscreenElement?: Element; webkitExitFullscreen?: () => void };
    const isActive =
      document.fullscreenElement === container || doc.webkitFullscreenElement === container;

    if (isActive) {
      if (document.exitFullscreen) await document.exitFullscreen().catch(() => undefined);
      else doc.webkitExitFullscreen?.();
      return;
    }

    const containerTarget = container as HTMLDivElement & { webkitRequestFullscreen?: () => void };
    if (container.requestFullscreen) {
      try {
        await container.requestFullscreen();
        return;
      } catch {
        // Fall through to video-native fullscreen on iOS.
      }
    }

    if (containerTarget.webkitRequestFullscreen) {
      containerTarget.webkitRequestFullscreen();
      return;
    }

    const videoTarget = video as HTMLVideoElement & {
      webkitEnterFullscreen?: () => void;
      webkitRequestFullscreen?: () => void;
    };

    if (videoTarget.webkitEnterFullscreen) {
      videoTarget.webkitEnterFullscreen();
      return;
    }

    await videoTarget.requestFullscreen?.().catch(() => undefined);
  };

  const deliveryLabel =
    deliveryMode === "webrtc-hls" ? "P2P WebRTC" : deliveryMode === "webrtc-fallback" ? "P2P HLS" : "P2P HLS";

  return (
    <div
      ref={containerRef}
      className={cn(
        "flex h-full w-full min-h-0 flex-col bg-black",
        isFullscreen && "h-dvh justify-center"
      )}
    >
      <div
        className={cn(
          "relative w-full min-h-[200px] overflow-hidden bg-black",
          isFullscreen ? "flex-1" : "aspect-video max-h-[min(56vh,520px)] sm:max-h-[min(60vh,600px)] md:aspect-auto md:h-full md:max-h-none"
        )}
        onMouseMove={() => revealTopChrome()}
        onTouchStart={() => revealTopChrome(false)}
      >
        <video
          ref={videoRef}
          className="h-full w-full object-contain"
          playsInline
          poster={poster}
          onClick={togglePlay}
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          onWaiting={() => {
            if (!hasStartedRef.current) return;
            if (!liveRecoveryTimerRef.current) {
              liveRecoveryTimerRef.current = setTimeout(() => {
                liveRecoveryTimerRef.current = null;
                const hls = hlsRef.current;
                if (!hls || !videoRef.current || playbackErrorRef.current) return;
                const liveSyncPosition = hls.liveSyncPosition;
                if (
                  typeof liveSyncPosition === "number" &&
                  Number.isFinite(liveSyncPosition) &&
                  videoRef.current.currentTime < liveSyncPosition - LIVE_EDGE_DRIFT_SEC
                ) {
                  videoRef.current.currentTime = liveSyncPosition;
                }
                hls.startLoad();
              }, 1500);
            }
            if (stallOverlayTimerRef.current) return;
            stallOverlayTimerRef.current = setTimeout(() => {
              stallOverlayTimerRef.current = null;
              setIsBuffering(true);
              onStallRef.current?.();
              logStreamDiagnostic("playback_stalled", { playbackMode: "p2p" });
            }, STALL_OVERLAY_MS);
          }}
          onPlaying={() => {
            if (stallOverlayTimerRef.current) {
              clearTimeout(stallOverlayTimerRef.current);
              stallOverlayTimerRef.current = null;
            }
            if (liveRecoveryTimerRef.current) {
              clearTimeout(liveRecoveryTimerRef.current);
              liveRecoveryTimerRef.current = null;
            }
            setIsBuffering(false);
            setPlaybackError(null);
            onRecoverRef.current?.();
            logStreamDiagnostic("playback_recovered", { playbackMode: "p2p" });
          }}
          onCanPlay={() => setIsBuffering(false)}
          onError={() => {
            if (recoverFromVideoElementError("video_element")) return;
            reportFailure("Playback could not start from this source.", "video_element");
          }}
        />

        {(!streamSrc || (isBuffering && !hasPlaybackStarted)) && !playbackError && (
          <div className="pointer-events-none absolute inset-0 z-20 grid place-items-center">
            <div className="flex items-center gap-3 rounded-full border border-white/10 bg-black/55 px-4 py-2 text-xs font-bold text-white backdrop-blur-md">
              <LoaderCircle size={14} className="animate-spin text-accent" />
              Preparing P2P stream…
            </div>
          </div>
        )}

        {isBuffering && hasPlaybackStarted && !playbackError && (
          <div className="pointer-events-none absolute bottom-20 left-1/2 z-20 -translate-x-1/2">
            <div className="flex items-center gap-2 rounded-full border border-white/10 bg-black/55 px-3 py-1.5 text-[10px] font-bold text-white backdrop-blur-md">
              <LoaderCircle size={12} className="animate-spin text-accent" />
              Buffering…
            </div>
          </div>
        )}

        {playbackError && (
          <div className="absolute inset-x-4 top-1/2 z-20 -translate-y-1/2 rounded-lg border border-white/10 bg-black/70 p-4 text-center text-white backdrop-blur-md">
            <p className="text-sm font-black">Playback unavailable</p>
            <p className="mt-1 text-xs font-medium text-white/65">{playbackError}</p>
            <button
              type="button"
              onClick={retryPlayback}
              className="mt-3 inline-flex min-h-10 items-center rounded-full border border-white/15 bg-white/10 px-4 text-xs font-black text-white"
            >
              Retry stream
            </button>
          </div>
        )}

        <div
          className={cn(
            "absolute inset-x-0 top-0 z-20 bg-gradient-to-b from-black/80 via-black/25 to-transparent transition-opacity duration-300",
            showTopChrome || !isPlaying ? "pointer-events-auto opacity-100" : "pointer-events-none opacity-0"
          )}
        >
          <div className="flex items-center justify-between p-4">
            <div className="flex min-w-0 items-center gap-2">
              <div className="rounded bg-live px-2 py-0.5 text-[8px] font-black uppercase italic">LIVE</div>
              <span className="truncate text-xs font-bold text-white shadow-sm">{title}</span>
            </div>
            <div className="flex items-center gap-1 rounded-full border border-white/10 bg-black/25 px-2.5 py-1 text-[10px] font-bold uppercase text-white/80">
              <Radio size={11} className="text-live" />
              {deliveryLabel}
            </div>
          </div>
        </div>

        {needsUnmute && isPlaying && isMuted && (
          <button
            type="button"
            onClick={toggleMute}
            className="absolute bottom-4 left-1/2 z-20 -translate-x-1/2 rounded-full border border-white/15 bg-black/70 px-4 py-2 text-xs font-bold text-white backdrop-blur-md"
          >
            Tap for sound
          </button>
        )}

        {!isPlaying && !playbackError && (
          <div className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center">
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                togglePlay();
              }}
              className="pointer-events-auto flex h-16 w-16 items-center justify-center rounded-full glass"
              aria-label="Play stream"
            >
              <Play fill="white" size={24} className="ml-1" />
            </button>
          </div>
        )}
      </div>

      <div
        className="flex shrink-0 items-center justify-between gap-3 border-t border-white/10 bg-background px-3 py-2.5 sm:px-4 sm:py-3"
        data-fotty-player-controls="dock"
      >
        <div className="flex min-w-0 items-center gap-4">
          <button
            type="button"
            onClick={togglePlay}
            className="text-white"
            aria-label={isPlaying ? "Pause" : "Play"}
          >
            {isPlaying ? <Pause size={22} fill="white" /> : <Play size={22} fill="white" />}
          </button>
          <button
            type="button"
            onClick={toggleMute}
            className="text-white"
            aria-label={isMuted ? "Unmute" : "Mute"}
          >
            {isMuted ? <VolumeX size={22} /> : <Volume2 size={22} />}
          </button>
          <span className="hidden truncate text-xs font-semibold text-text-secondary sm:inline">{title}</span>
        </div>

        <button
          type="button"
          className="inline-flex items-center gap-2 text-xs font-bold text-white/85 transition-colors hover:text-white"
          onClick={() => void openFullscreen()}
          aria-label={isFullscreen ? "Exit fullscreen" : "Enter fullscreen"}
        >
          {isFullscreen ? <Minimize size={18} /> : <Maximize size={18} />}
          <span className="hidden sm:inline">{isFullscreen ? "Exit" : "Fullscreen"}</span>
        </button>
      </div>
    </div>
  );
};
