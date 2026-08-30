import type { ScrapedMatch } from "@/lib/api";

export type SportFilterId =
  | "all"
  | "football"
  | "basketball"
  | "baseball"
  | "combat"
  | "motorsport"
  | "american-football"
  | "hockey"
  | "cricket";

export interface SportPill {
  id: SportFilterId;
  label: string;
  emoji: string;
}

export const SPORT_FILTER_PILLS: readonly SportPill[] = [
  { id: "all", label: "All Sports", emoji: "🌐" },
  { id: "football", label: "Football", emoji: "⚽" },
  { id: "basketball", label: "Basketball", emoji: "🏀" },
  { id: "baseball", label: "Baseball", emoji: "⚾" },
  { id: "combat", label: "Combat", emoji: "🥊" },
  { id: "motorsport", label: "Motorsport", emoji: "🏎️" },
  { id: "american-football", label: "American Football", emoji: "🏈" },
  { id: "hockey", label: "Hockey", emoji: "🏒" },
  { id: "cricket", label: "Cricket", emoji: "🏏" },
] as const;

export function matchMatchesSport(match: ScrapedMatch, sportId: string): boolean {
  if (!sportId || sportId === "all") return true;

  const sportLower = (match.sport || "").toLowerCase();
  const leagueLower = (match.league || "").toLowerCase();
  const titleLower = (match.title || "").toLowerCase();
  const categories = (match.categories || []).map((c) => c.toLowerCase());

  const fullText = [
    sportLower,
    leagueLower,
    titleLower,
    match.displayTitle?.toLowerCase(),
    match.subtitle?.toLowerCase(),
    ...categories,
  ]
    .filter(Boolean)
    .join(" ");

  switch (sportId) {
    case "football":
      return (
        sportLower === "football" ||
        categories.includes("football") ||
        /premier league|champions league|la liga|serie a|bundesliga|ligue 1|mls|ucl|uel|uefa|fifa|copa|eredivisie|primeira liga|scottish premiership|soccer|arsenal|chelsea|liverpool|manchester|real madrid|barcelona|juventus|inter|milan|bayern|dortmund|psg/i.test(
          fullText
        )
      );
    case "basketball":
      return (
        sportLower === "basketball" ||
        categories.includes("basketball") ||
        /nba|wnba|euroleague|basketball|celtics|lakers|warriors|nuggets|bucks|heat/i.test(fullText)
      );
    case "baseball":
      return (
        sportLower === "baseball" ||
        categories.includes("baseball") ||
        /mlb|baseball|yankees|red sox|dodgers|astros|mariners|cubs|mets|braves|phillies/i.test(fullText)
      );
    case "combat":
      return (
        sportLower.includes("combat") ||
        sportLower.includes("fight") ||
        categories.includes("combat") ||
        categories.includes("fight") ||
        /ufc|boxing|mma|bellator|one championship|pfl|fight/i.test(fullText)
      );
    case "motorsport":
      return (
        sportLower.includes("motor") ||
        categories.includes("motorsport") ||
        /formula 1|f1|motogp|nascar|indycar|rally/i.test(fullText)
      );
    case "american-football":
      return (
        sportLower.includes("american") ||
        categories.includes("american football") ||
        /nfl|ncaa football|super bowl|touchdown|packers|chiefs|cowboys|patriots|eagles|49ers/i.test(fullText)
      );
    case "hockey":
      return (
        sportLower === "hockey" ||
        categories.includes("hockey") ||
        /nhl|khl|hockey|stanley cup|bruins|maple leafs|rangers|oilers/i.test(fullText)
      );
    case "cricket":
      return (
        sportLower === "cricket" ||
        categories.includes("cricket") ||
        /cricket|ipl|test match|t20|odi|bbl|the hundred|cpl/i.test(fullText)
      );
    default:
      return true;
  }
}
