"use client";

import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import type { LucideIcon } from 'lucide-react';
import { Activity, Clock, Database, Layers, Radio, ShieldCheck, SlidersHorizontal, Users, X } from 'lucide-react';

interface PlaybackWarmupProps {
  title: string;
  peerCount: number;
  speedKbps: number;
  bufferSeconds: number;
  readySegments: number;
  statusMessage: string;
  sourceId?: string;
  sessionId?: string | null;
  startedAt?: number;
  hasTelemetry?: boolean;
  onCancel: () => void;
  onSkip?: () => void;
}

export const PlaybackWarmup: React.FC<PlaybackWarmupProps> = ({
  title,
  peerCount,
  speedKbps,
  bufferSeconds,
  readySegments,
  statusMessage,
  sourceId,
  sessionId,
  startedAt,
  hasTelemetry,
  onCancel,
  onSkip
}) => {
  const [now, setNow] = useState(() => Date.now());
  const [showDetails, setShowDetails] = useState(false);

  useEffect(() => {
    const interval = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(interval);
  }, []);

  const elapsedSeconds = startedAt ? Math.max(0, Math.floor((now - startedAt) / 1000)) : 0;
  const phase = sessionId ? "Broker session created" : elapsedSeconds > 8 ? "Still asking broker for a session" : "Creating broker session";
  const telemetryReady = Boolean(hasTelemetry);
  const healthLabel = telemetryReady
    ? (peerCount ?? 0) > 5
      ? "Strong"
      : readySegments > 0
        ? "Ready"
        : "Warming"
    : "Pending";
  const bufferLabel = telemetryReady ? `${bufferSeconds ?? 0}s` : "Waiting";
  const peersLabel = telemetryReady ? (peerCount ?? 0).toString() : "Waiting";
  const segmentsLabel = telemetryReady ? (readySegments ?? 0).toString() : "Waiting";
  const shortSession = useMemo(() => {
    if (!sessionId) return "Not issued yet";
    return sessionId.length > 14 ? `${sessionId.slice(0, 8)}...${sessionId.slice(-4)}` : sessionId;
  }, [sessionId]);
  const activityLabel = telemetryReady || sessionId ? "Finding the best signal" : "Tuning stream";

  return (
    <motion.div 
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-[100] flex min-h-dvh flex-col items-center justify-between overflow-y-auto bg-background px-md py-[calc(1.25rem+env(safe-area-inset-top))] pb-[calc(1.25rem+env(safe-area-inset-bottom))] sm:py-16"
    >
      <div className="flex flex-col items-center gap-2 text-center">
        <div className="flex items-center gap-2 rounded-full border border-accent/20 bg-accent/10 px-3 py-1">
          <div className="h-1.5 w-1.5 animate-pulse rounded-full bg-accent" />
          <span className="text-[10px] font-black uppercase tracking-widest text-accent">Tuning in</span>
        </div>
        <h2 className="line-clamp-2 text-xl font-black sm:text-2xl">{title}</h2>
      </div>

      <div className="flex w-full max-w-[520px] flex-col items-center gap-5">
        <TuningOrb telemetryReady={telemetryReady} />

        <div className="flex items-center gap-2 rounded-full border border-white/10 bg-surface/80 px-4 py-2 text-xs font-black text-text-secondary shadow-2xl shadow-black/20">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-accent" />
          {activityLabel}
        </div>

        <button
          type="button"
          onClick={() => setShowDetails((value) => !value)}
          className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-[11px] font-black text-text-secondary transition-colors hover:bg-white/10"
        >
          <SlidersHorizontal size={13} />
          {showDetails ? "Hide details" : "Details"}
        </button>

        {showDetails ? (
          <>
            <div className="w-full rounded-lg border border-white/10 bg-surface px-4 py-3">
              <div className="grid gap-3 text-xs font-bold text-text-secondary sm:grid-cols-2">
                <DiagnosticLine icon={Radio} label="Source" value={sourceId || "Unknown channel"} />
                <DiagnosticLine icon={Activity} label="Session" value={shortSession} />
                <DiagnosticLine icon={Database} label="Downlink" value={telemetryReady ? `${speedKbps ?? 0} kbps` : "Waiting"} />
                <DiagnosticLine icon={Clock} label="Step" value={`${phase} · ${elapsedSeconds}s`} />
                <DiagnosticLine icon={ShieldCheck} label="Status" value={statusMessage || "Preparing stream"} />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 w-full max-w-[340px] px-md">
              <MetricItem icon={Users} label="Peers" value={peersLabel} color="text-blue-400" />
              <MetricItem icon={Database} label="Buffer" value={bufferLabel} color="text-amber-400" />
              <MetricItem icon={Layers} label="Segments" value={segmentsLabel} color="text-success" />
              <MetricItem icon={ShieldCheck} label="Health" value={healthLabel} color="text-text-secondary" />
            </div>
          </>
        ) : null}
      </div>

      {/* Bottom Status */}
      <div className="flex w-full flex-col items-center gap-4">
        <div className="flex flex-col gap-4 items-center">
          {onSkip && (
            <button 
              onClick={onSkip}
              className="px-8 py-3 rounded-full glass border border-white/10 text-xs font-black uppercase italic tracking-wider hover:bg-white/5 transition-colors"
            >
              Skip & Play Now
            </button>
          )}
          
          <button 
            onClick={onCancel}
            className="flex items-center gap-2 text-text-tertiary font-black uppercase italic tracking-widest text-[10px] py-2 px-4 hover:text-error transition-colors"
          >
            <X size={14} /> Cancel Session
          </button>
        </div>
      </div>
    </motion.div>
  );
};

function TuningOrb({ telemetryReady }: { telemetryReady: boolean }) {
  const bars = [0, 1, 2, 3, 4];

  return (
    <div className="relative grid h-56 w-56 place-items-center">
      <motion.div
        className="absolute h-48 w-48 rounded-full border border-accent/15"
        animate={{ scale: [0.82, 1.12, 0.82], opacity: [0.35, 0.05, 0.35] }}
        transition={{ duration: 2.4, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="absolute h-36 w-36 rounded-full border border-live/20"
        animate={{ scale: [1, 1.28, 1], opacity: [0.25, 0.06, 0.25] }}
        transition={{ duration: 2.8, repeat: Infinity, ease: "easeInOut", delay: 0.2 }}
      />
      <div className="relative grid h-32 w-32 place-items-center rounded-full border border-white/10 bg-surface shadow-2xl shadow-accent/10">
        <Radio size={34} className={telemetryReady ? "text-live" : "text-accent"} />
        <div className="absolute bottom-7 flex items-end gap-1">
          {bars.map((bar) => (
            <motion.span
              key={bar}
              className={telemetryReady ? "w-1 rounded-full bg-live" : "w-1 rounded-full bg-accent"}
              animate={{ height: [8, 18 + bar * 3, 8], opacity: [0.45, 1, 0.45] }}
              transition={{ duration: 1, repeat: Infinity, delay: bar * 0.12 }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function DiagnosticLine({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="flex min-w-0 items-center gap-2">
      <Icon size={13} className="shrink-0 text-accent" />
      <span className="shrink-0 text-[10px] uppercase tracking-widest text-text-tertiary">{label}</span>
      <span className="min-w-0 truncate text-text-primary">{value}</span>
    </div>
  );
}

function MetricItem({ icon: Icon, label, value, color }: { icon: LucideIcon; label: string; value: string; color: string }) {
  return (
    <div className="glass px-4 py-3 rounded-md flex flex-col gap-1 min-w-0 border border-white/5">
      <div className="flex items-center gap-2 text-text-tertiary">
        <Icon size={12} className={color} />
        <span className="text-[10px] font-bold uppercase tracking-widest truncate">{label}</span>
      </div>
      <div className="text-lg font-black tabular-nums truncate">{value}</div>
    </div>
  );
}
