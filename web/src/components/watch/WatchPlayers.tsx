"use client";

import React, { forwardRef, useCallback, useEffect, useImperativeHandle, useRef } from "react";
import { LoadingState, NoVerifiedStreamState } from "@/components/FallbackState";
import { resolveEventEmbedIframeSrc } from "@/lib/stream-guide/embed-url";
import { v2AppPath, v2HomePath } from "@/lib/v2/preview";

export function watchUnavailableTitle(message?: string | null) {
  const normalized = message?.toLowerCase() || "";
  if (/(sign[- ]?in|session|secure watch|refresh access)/.test(normalized)) {
    return "Refresh your watch session";
  }
  if (/(active live access|paid fotty|paid plan|live access|required to watch|without active watch access)/.test(normalized)) {
    return "Live access required";
  }
  if (/(broker|could not reach|prepare this source|did not return a session)/.test(normalized)) {
    return "Stream source unavailable";
  }
  return "No verified watch path yet";
}

export type DirectEventPlayerHandle = {
  unmute: () => void;
  startPlayback: () => void;
};

export const DirectEventPlayer = forwardRef<DirectEventPlayerHandle, {
  title: string;
  embedURL: string | null;
  streamKey?: string;
  eventSource?: { source: string; id: string; streamNo: number };
  isLoading: boolean;
  error: string | null;
  returnTo?: string;
  onFrameLoad?: (embedURL: string) => void;
  onFrameError?: (embedURL: string) => void;
  onPlaybackStarted?: () => void;
  onPlaybackStalled?: (embedURL: string) => void;
  onPlaybackPulse?: () => void;
  onDirectFallbackChange?: (active: boolean) => void;
  onRetry?: () => void;
  onEmbedIframeRef?: (iframe: HTMLIFrameElement | null) => void;
}>(function DirectEventPlayer({
  title,
  embedURL,
  streamKey,
  eventSource,
  isLoading,
  error,
  returnTo,
  onFrameLoad,
  onFrameError,
  onPlaybackStarted,
  onPlaybackStalled,
  onPlaybackPulse,
  onRetry,
  onEmbedIframeRef,
  onDirectFallbackChange,
}, ref) {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const embedErrorReportedRef = useRef(false);
  const playerKey = `${streamKey || "event"}:${embedURL || ""}:${eventSource?.source || ""}:${eventSource?.id || ""}:${eventSource?.streamNo || 1}`;

  const assignIframeRef = useCallback(
    (node: HTMLIFrameElement | null) => {
      iframeRef.current = node;
      onEmbedIframeRef?.(node);
    },
    [onEmbedIframeRef]
  );

  const unmute = useCallback(() => {
    // Cross-origin provider player: focus the frame so the user can hit its volume control.
    // postMessage only works for same-origin proxied players with Fotty injection.
    iframeRef.current?.contentWindow?.postMessage({ type: "fotty:unmute" }, "*");
    iframeRef.current?.focus();
    try {
      iframeRef.current?.contentWindow?.focus();
    } catch {
      // ignore
    }
  }, []);

  useImperativeHandle(
    ref,
    () => ({
      unmute,
      startPlayback: () => {
        iframeRef.current?.contentWindow?.postMessage({ type: "fotty:play" }, "*");
      },
    }),
    [unmute]
  );

  useEffect(() => {
    embedErrorReportedRef.current = false;
    onDirectFallbackChange?.(false);
  }, [embedURL, playerKey, onDirectFallbackChange]);

  useEffect(() => {
    const handlePlaybackMessage = (event: MessageEvent) => {
      if (event.source !== iframeRef.current?.contentWindow) return;
      const messageType =
        event.data && typeof event.data === "object"
          ? (event.data as { type?: unknown }).type
          : undefined;
      if (typeof messageType !== "string") return;

      switch (messageType) {
        case "fotty:playback-started":
          onPlaybackStarted?.();
          break;
        case "fotty:playback-pulse":
          onPlaybackPulse?.();
          break;
        case "fotty:playback-stalled":
        case "fotty:playback-error":
          if (embedURL) onPlaybackStalled?.(embedURL);
          break;
        default:
          break;
      }
    };

    window.addEventListener("message", handlePlaybackMessage);
    return () => window.removeEventListener("message", handlePlaybackMessage);
  }, [embedURL, onPlaybackPulse, onPlaybackStalled, onPlaybackStarted]);

  if (isLoading) {
    return (
      <div className="absolute inset-0 grid place-items-center bg-black">
        <LoadingState
          title="Checking watch path"
          message="Fotty is preparing the best available match stream."
          compact
          className="w-full max-w-[520px] bg-surface/45"
        />
      </div>
    );
  }

  if (error || !embedURL) {
    return (
      <div className="absolute inset-0">
        <UnavailablePlayer
          title={watchUnavailableTitle(error)}
          message={error || "Fotty could not verify this watch path. Try another feed, or go back to Home."}
          href={returnTo || v2HomePath()}
          guideHref={v2AppPath("/search")}
          onRetry={onRetry}
        />
      </div>
    );
  }

  const iframeSrc = resolveEventEmbedIframeSrc(embedURL, eventSource?.source);

  return (
    <div className="absolute inset-0 isolate overflow-hidden bg-black">
      <iframe
        ref={assignIframeRef}
        key={playerKey}
        title={title}
        src={iframeSrc}
        className="absolute inset-0 h-full w-full border-0 bg-black"
        allow="autoplay; fullscreen; picture-in-picture; encrypted-media; accelerometer; gyroscope; clipboard-write; web-share"
        allowFullScreen
        referrerPolicy="no-referrer"
        loading="eager"
        onLoad={() => {
          onFrameLoad?.(embedURL);
        }}
        onError={() => {
          if (embedErrorReportedRef.current) return;
          embedErrorReportedRef.current = true;
          onFrameError?.(embedURL);
        }}
      />
    </div>
  );
});

export function UnavailablePlayer({
  title,
  message,
  href,
  guideHref,
  onRetry,
  retryLabel = "Try again",
  onBrowseLive,
  sourceLabel,
}: {
  title: string;
  message: string;
  href?: string;
  guideHref?: string;
  onRetry?: () => void;
  retryLabel?: string;
  onBrowseLive?: () => void;
  sourceLabel?: string;
}) {
  return (
    <div className="grid h-full w-full place-items-center bg-black px-5 py-14 text-center sm:px-8">
      <NoVerifiedStreamState
        title={title}
        message={sourceLabel ? `${sourceLabel}: ${message}` : message}
        primaryAction={onRetry ? { label: retryLabel, onClick: onRetry } : href ? { label: "Back to Live", href } : { label: "Back to Live", onClick: onBrowseLive }}
        secondaryAction={guideHref ? { label: "Discover", href: guideHref } : undefined}
        className="w-full max-w-[680px] bg-surface/50"
      />
    </div>
  );
}
