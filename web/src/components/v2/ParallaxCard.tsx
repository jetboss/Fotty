"use client";

import React, { useState, useRef } from "react";
import { motion, useMotionValue, useSpring, useTransform } from "framer-motion";

interface ParallaxCardProps {
  children: React.ReactNode;
  active?: boolean;
}

export function ParallaxCard({ children, active = true }: ParallaxCardProps) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [hovered, setHovered] = useState(false);

  // Motion values for normalized mouse positions (-0.5 to 0.5)
  const x = useMotionValue(0);
  const y = useMotionValue(0);

  // Smooth springs for 3D rotation
  const rotateX = useSpring(useTransform(y, [-0.5, 0.5], [8, -8]), { stiffness: 120, damping: 18 });
  const rotateY = useSpring(useTransform(x, [-0.5, 0.5], [-8, 8]), { stiffness: 120, damping: 18 });
  
  // Highlight sheen reflection positions
  const highlightX = useTransform(x, [-0.5, 0.5], ["0%", "100%"]);
  const highlightY = useTransform(y, [-0.5, 0.5], ["0%", "100%"]);

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!active || !cardRef.current) return;
    const rect = cardRef.current.getBoundingClientRect();
    const width = rect.width;
    const height = rect.height;
    const mouseX = e.clientX - rect.left - width / 2;
    const mouseY = e.clientY - rect.top - height / 2;
    x.set(mouseX / width);
    y.set(mouseY / height);
  };

  const handleMouseLeave = () => {
    setHovered(false);
    x.set(0);
    y.set(0);
  };

  if (!active) {
    return <>{children}</>;
  }

  return (
    <div
      ref={cardRef}
      onMouseMove={handleMouseMove}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={handleMouseLeave}
      style={{ perspective: 1000 }}
      className="relative select-none"
    >
      <motion.div
        style={{ rotateX, rotateY, transformStyle: "preserve-3d" }}
        className="relative rounded-xl"
      >
        {children}
        
        {/* Glow & Reflection Overlays */}
        {hovered && (
          <>
            {/* Dynamic Highlight reflection overlay */}
            <motion.div
              style={{
                background: `radial-gradient(circle at ${highlightX} ${highlightY}, rgba(255,255,255,0.12) 0%, transparent 60%)`,
              }}
              className="absolute inset-0 pointer-events-none rounded-xl mix-blend-overlay z-20"
            />
            {/* Outer border flare */}
            <div className="absolute inset-0 border border-white/12 rounded-xl pointer-events-none z-30" />
          </>
        )}
      </motion.div>
    </div>
  );
}
