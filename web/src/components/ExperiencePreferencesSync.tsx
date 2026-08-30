"use client";

import { useEffect } from "react";
import { purgeLegacyWatchHistory } from "@/lib/storage";
import { useUserPreferences } from "@/lib/user-experience";

if (typeof window !== "undefined") {
  const originalFetch = window.fetch;
  window.fetch = function (input, init) {
    if (typeof input === "string") {
      const apiBase = process.env.NEXT_PUBLIC_API_BASE || "";
      if (apiBase) {
        if (input.startsWith("/api/")) {
          input = `${apiBase}${input}`;
        } else if (input.startsWith(window.location.origin + "/api/")) {
          input = input.replace(window.location.origin, apiBase);
        }
      }
    }
    return originalFetch(input, init);
  };
}

export function ExperiencePreferencesSync() {
  const { preferences } = useUserPreferences();

  useEffect(() => {
    purgeLegacyWatchHistory();
  }, []);

  useEffect(() => {
    document.body.dataset.compactMode = preferences.compactMode ? "true" : "false";
    document.body.dataset.autoPlayHighlights = preferences.autoPlayHighlights ? "true" : "false";
  }, [preferences.autoPlayHighlights, preferences.compactMode]);

  return null;
}
