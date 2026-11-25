"use client";

import React, { forwardRef } from "react";

export const WatchVideoStage = forwardRef<
  HTMLDivElement,
  { children: React.ReactNode; v2?: boolean }
>(function WatchVideoStage({ children, v2 = false }, ref) {
  return (
    <div ref={ref} className="relative flex w-full shrink-0 flex-col bg-black">
      <div
        className={
          v2
            ? "relative h-[48svh] min-h-[240px] max-h-[480px] w-full overflow-hidden sm:aspect-video sm:h-auto sm:min-h-[280px] sm:max-h-[min(62svh,600px)] lg:aspect-auto lg:h-[min(68svh,860px)] lg:max-h-[78svh] lg:min-h-[400px]"
            : "relative h-[42svh] min-h-[220px] max-h-[430px] w-full overflow-hidden sm:aspect-video sm:h-auto sm:min-h-[260px] sm:max-h-[min(58svh,560px)] md:aspect-auto md:h-[min(62svh,820px)] md:max-h-[75svh] md:min-h-[360px]"
        }
        data-pull-refresh-ignore
      >
        {children}
      </div>
    </div>
  );
});
