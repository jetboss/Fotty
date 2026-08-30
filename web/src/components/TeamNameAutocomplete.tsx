"use client";

import React, { useEffect, useId, useMemo, useRef, useState } from "react";
import { FottyAPI } from "@/lib/api";
import {
  buildTeamCatalogFromMatches,
  findSuggestionMatch,
  searchTeamSuggestions,
  type TeamSuggestion,
} from "@/lib/team-catalog";
import { cn } from "@/lib/utils";

interface TeamNameAutocompleteProps {
  value: string;
  onChange: (value: string) => void;
  onSelect?: (suggestion: TeamSuggestion) => void;
  placeholder?: string;
  inputId?: string;
  className?: string;
}

export function TeamNameAutocomplete({
  value,
  onChange,
  onSelect,
  placeholder = "Add a team, e.g. Arsenal",
  inputId,
  className,
}: TeamNameAutocompleteProps) {
  const listId = useId();
  const containerRef = useRef<HTMLDivElement>(null);
  const [catalog, setCatalog] = useState<TeamSuggestion[]>(() => buildTeamCatalogFromMatches([]));
  const [isFocused, setIsFocused] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);

  useEffect(() => {
    let cancelled = false;

    FottyAPI.fetchMatches()
      .then((matches) => {
        if (!cancelled) setCatalog(buildTeamCatalogFromMatches(matches));
      })
      .catch(() => {
        // Keep the static football catalog when the feed is unavailable.
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const suggestions = useMemo(() => searchTeamSuggestions(value, catalog, 8), [catalog, value]);
  const showSuggestions = isFocused && suggestions.length > 0;

  useEffect(() => {
    setActiveIndex(0);
  }, [value, suggestions.length]);

  useEffect(() => {
    const handlePointerDown = (event: MouseEvent) => {
      if (!containerRef.current?.contains(event.target as Node)) {
        setIsFocused(false);
      }
    };

    const handleScroll = () => setIsFocused(false);

    window.addEventListener("pointerdown", handlePointerDown);
    window.addEventListener("scroll", handleScroll, true);
    return () => {
      window.removeEventListener("pointerdown", handlePointerDown);
      window.removeEventListener("scroll", handleScroll, true);
    };
  }, []);

  const chooseSuggestion = (suggestion: TeamSuggestion) => {
    onChange(suggestion.name);
    onSelect?.(suggestion);
    setIsFocused(false);
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (!showSuggestions) return;

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((index) => (index + 1) % suggestions.length);
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) => (index - 1 + suggestions.length) % suggestions.length);
      return;
    }

    if (event.key === "Enter" && suggestions[activeIndex]) {
      event.preventDefault();
      chooseSuggestion(suggestions[activeIndex]);
      return;
    }

    if (event.key === "Escape") {
      setIsFocused(false);
    }
  };

  return (
    <div ref={containerRef} className={cn("relative z-0 min-w-0 flex-1", className)}>
      <label className="sr-only" htmlFor={inputId}>
        Team name
      </label>
      <input
        id={inputId}
        value={value}
        role="combobox"
        aria-expanded={showSuggestions}
        aria-controls={listId}
        aria-autocomplete="list"
        autoComplete="off"
        onChange={(event) => {
          onChange(event.target.value);
          setIsFocused(true);
        }}
        onFocus={() => setIsFocused(true)}
        onBlur={() => {
          window.setTimeout(() => setIsFocused(false), 120);
        }}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        className="min-h-12 w-full select-text rounded-lg border border-white/10 bg-background px-4 text-sm font-semibold text-text-primary outline-none placeholder:text-text-tertiary focus:border-accent/40"
      />

      {showSuggestions && (
        <ul
          id={listId}
          role="listbox"
          className="absolute left-0 right-0 top-[calc(100%+0.35rem)] z-30 max-h-64 overflow-y-auto rounded-xl border border-white/10 bg-surface-elevated p-1 shadow-2xl"
        >
          {suggestions.map((suggestion, index) => (
            <li key={`${suggestion.name}:${suggestion.league || ""}`} role="presentation">
              <button
                type="button"
                role="option"
                aria-selected={index === activeIndex}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => chooseSuggestion(suggestion)}
                className={cn(
                  "flex w-full select-text items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left transition-colors",
                  index === activeIndex ? "bg-accent/15 text-text-primary" : "text-text-secondary hover:bg-white/5"
                )}
              >
                <span className="truncate text-sm font-bold text-text-primary">{suggestion.name}</span>
                <span className="shrink-0 text-[11px] font-semibold text-text-tertiary">
                  {[suggestion.league, suggestion.sport].filter(Boolean).join(" · ")}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function resolveTeamSelection(name: string, catalog: TeamSuggestion[]) {
  const trimmed = name.trim();
  if (!trimmed) return null;
  return findSuggestionMatch(trimmed, catalog) || { name: trimmed, sport: "Football" as const };
}
