/**
 * Estimated in-play clock for association football only.
 *
 * Baseball, basketball, hockey, American football, and similar sports need a
 * provider-owned inning/period/quarter clock. Treating wall-clock minutes since
 * the scheduled start as match time produces authoritative-looking nonsense
 * such as `115′` for a baseball game, so those sports deliberately return no
 * clock until the feed supplies one.
 */
export function estimateMatchClock(options: {
  startsAt?: string;
  sport?: string;
  apiStatus?: string;
  now?: number;
}): string | null {
  const normalized = options.apiStatus?.trim().toLowerCase() || "";
  if (normalized === "ht" || normalized === "half time" || normalized === "halftime") return "HT";
  if (normalized === "ft" || normalized === "full time" || normalized === "finished") return "FT";

  const sport = options.sport?.trim().toLowerCase() || "";
  const isAssociationFootball =
    sport.includes("soccer") ||
    (sport.includes("football") && !sport.includes("american"));
  if (!isAssociationFootball || !options.startsAt) return null;

  const kickoff = new Date(options.startsAt).getTime();
  if (!Number.isFinite(kickoff)) return null;

  const now = options.now ?? Date.now();
  const elapsedMin = Math.floor((now - kickoff) / 60_000);
  if (elapsedMin < 0 || elapsedMin > 125) return null;

  if (elapsedMin <= 45) return `${elapsedMin}'`;
  if (elapsedMin < 60) return "HT";
  const secondHalf = elapsedMin - 60 + 46;
  if (secondHalf >= 90) return `90+${secondHalf - 90}`;
  return `${secondHalf}'`;
}
