"use client";

import React, { useMemo } from "react";
import { motion, AnimatePresence } from "framer-motion";

import { resolveTeamColor } from "@/lib/v2/team-colors";

interface AmbientGlowProps {
  home?: string;
  away?: string;
}

export function AmbientGlow({ home, away }: AmbientGlowProps) {
  const homeColor = useMemo(() => resolveTeamColor(home), [home]);
  const awayColor = useMemo(() => resolveTeamColor(away), [away]);

  if (!homeColor && !awayColor) {
    // Subtle field turf green default glow
    return (
      <div className="absolute inset-0 pointer-events-none overflow-hidden z-0">
        <div className="absolute -left-[10%] -top-[20%] w-[60vw] h-[60vw] rounded-full bg-emerald-500/5 blur-[120px]" />
        <div className="absolute -right-[10%] -top-[20%] w-[60vw] h-[60vw] rounded-full bg-teal-500/5 blur-[120px]" />
        <div className="absolute bottom-0 inset-x-0 h-[30vh] bg-gradient-to-t from-[#0e2a14]/10 to-transparent blur-[80px]" />
      </div>
    );
  }

  return (
    <div className="absolute inset-0 pointer-events-none overflow-hidden z-0">
      <AnimatePresence mode="popLayout">
        {homeColor && (
          <motion.div
            key={`home-${homeColor}`}
            initial={{ opacity: 0 }}
            animate={{ opacity: 0.28 }} // Increased opacity for richer premium visibility
            exit={{ opacity: 0 }}
            transition={{ duration: 0.8, ease: "easeInOut" }}
            style={{ backgroundColor: homeColor }}
            className="absolute -left-[10%] -top-[20%] w-[60vw] h-[60vw] rounded-full blur-[130px]"
          />
        )}
      </AnimatePresence>
      
      <AnimatePresence mode="popLayout">
        {awayColor && (
          <motion.div
            key={`away-${awayColor}`}
            initial={{ opacity: 0 }}
            animate={{ opacity: 0.24 }} // Increased opacity for richer premium visibility
            exit={{ opacity: 0 }}
            transition={{ duration: 0.8, ease: "easeInOut" }}
            style={{ backgroundColor: awayColor }}
            className="absolute -right-[10%] -top-[20%] w-[60vw] h-[60vw] rounded-full blur-[130px]"
          />
        )}
      </AnimatePresence>

      {/* Bottom green grass/turf reflection glow */}
      <div className="absolute bottom-0 inset-x-0 h-[30vh] bg-gradient-to-t from-[#0e2a14]/20 to-transparent blur-[80px]" />
    </div>
  );
}
