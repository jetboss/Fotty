/** Per-team hues for poster fallbacks (kept in sync with TeamBadge logic). */
export function teamColorHash(name: string) {
  let hash = 0;
  for (const char of name) hash = (hash * 31 + char.charCodeAt(0)) % 360;
  return {
    from: `hsl(${hash} 58% 42%)`,
    to: `hsl(${(hash + 35) % 360} 68% 34%)`,
  };
}

export function matchPosterGradient(home: string, away: string) {
  const homeColors = teamColorHash(home);
  const awayColors = teamColorHash(away);
  return `linear-gradient(155deg, ${homeColors.from} 0%, ${awayColors.from} 42%, ${awayColors.to} 72%, #050505 100%)`;
}

export function shortTeamLabel(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length >= 2) {
    return parts
      .slice(0, 2)
      .map((part) => part.slice(0, 3).toUpperCase())
      .join(" ");
  }
  return name.slice(0, 3).toUpperCase();
}
