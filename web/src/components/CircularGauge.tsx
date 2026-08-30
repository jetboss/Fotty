"use client";

import React from 'react';
import { motion } from 'framer-motion';

interface CircularGaugeProps {
  value: number;
  max: number;
  label: string;
  unit: string;
  color?: string;
  size?: number;
}

export const CircularGauge: React.FC<CircularGaugeProps> = ({
  value,
  max,
  label,
  unit,
  color = "#E11F47",
  size = 140
}) => {
  const radius = size / 2 - 10;
  const circumference = 2 * Math.PI * radius;
  const progress = Math.min(value / max, 1);
  const strokeDashoffset = circumference * (1 - progress);

  return (
    <div className="relative flex flex-col items-center justify-center" style={{ width: size, height: size }}>
      {/* Background Circle */}
      <svg className="absolute transform -rotate-90" width={size} height={size}>
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke="currentColor"
          strokeWidth="4"
          fill="transparent"
          className="text-white/5"
        />
        {/* Progress Circle */}
        <motion.circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke={color}
          strokeWidth="4"
          fill="transparent"
          strokeDasharray={circumference}
          initial={{ strokeDashoffset: circumference }}
          animate={{ strokeDashoffset }}
          transition={{ duration: 1, ease: "easeOut" }}
          strokeLinecap="round"
        />
      </svg>

      {/* Central Metrics */}
      <div className="flex flex-col items-center text-center z-10">
        <span className="text-2xl font-black tabular-nums tracking-tighter">
          {Math.round(value || 0)}
        </span>
        <span className="text-[10px] font-bold text-text-tertiary uppercase">
          {unit}
        </span>
      </div>
      
      {/* Label under gauge */}
      <div className="absolute -bottom-2">
        <span className="text-[8px] font-black text-text-secondary uppercase tracking-widest bg-surface px-2 py-0.5 rounded border border-white/5">
          {label}
        </span>
      </div>
    </div>
  );
};
