/** ISO codes for https://flagcdn.com — longest name match wins. */
const COUNTRY_FLAG_CODES: Record<string, string> = {
  "south africa": "za",
  "south korea": "kr",
  "saudi arabia": "sa",
  "united states": "us",
  "new zealand": "nz",
  "costa rica": "cr",
  "bosnia-herzegovina": "ba",
  "bosnia": "ba",
  "ivory coast": "ci",
  "czechia": "cz",
  "czech": "cz",
  argentina: "ar",
  australia: "au",
  austria: "at",
  belgium: "be",
  brazil: "br",
  canada: "ca",
  chile: "cl",
  china: "cn",
  colombia: "co",
  croatia: "hr",
  denmark: "dk",
  ecuador: "ec",
  egypt: "eg",
  england: "gb-eng",
  finland: "fi",
  france: "fr",
  germany: "de",
  ghana: "gh",
  honduras: "hn",
  hungary: "hu",
  india: "in",
  iran: "ir",
  italy: "it",
  japan: "jp",
  korea: "kr",
  mexico: "mx",
  morocco: "ma",
  netherlands: "nl",
  nigeria: "ng",
  norway: "no",
  paraguay: "py",
  peru: "pe",
  poland: "pl",
  portugal: "pt",
  qatar: "qa",
  romania: "ro",
  russia: "ru",
  scotland: "gb-sct",
  senegal: "sn",
  serbia: "rs",
  slovakia: "sk",
  spain: "es",
  sweden: "se",
  switzerland: "ch",
  turkey: "tr",
  ukraine: "ua",
  uruguay: "uy",
  usa: "us",
  wales: "gb-wls",
  algeria: "dz",
  cameroon: "cm",
  panama: "pa",
  bolivia: "bo",
  venezuela: "ve",
  tunisia: "tn",
  jordan: "jo",
  uzbekistan: "uz",
};

const COUNTRY_KEYS_LONGEST_FIRST = Object.keys(COUNTRY_FLAG_CODES).sort(
  (left, right) => right.length - left.length
);

export function isFlagEmoji(value?: string) {
  return Boolean(value && /[\p{Regional_Indicator}\p{Extended_Pictographic}]/u.test(value));
}

function countryKeyForTeam(name: string) {
  const lower = name.toLowerCase().trim();
  return COUNTRY_KEYS_LONGEST_FIRST.find((key) => lower.includes(key));
}

function flagCdnSrc(name: string) {
  const key = countryKeyForTeam(name);
  if (!key) return undefined;
  return `https://flagcdn.com/w160/${COUNTRY_FLAG_CODES[key]}.png`;
}

function streamedBadgeSlugSrc(badge: string) {
  if (badge.startsWith("http://") || badge.startsWith("https://") || badge.startsWith("/")) {
    return badge;
  }
  // Same token → streamed.pk crest path the iOS app builds via AnalyticalDataEngine.imageURL.
  if (badge.length <= 4 || badge.includes("/")) return undefined;
  if (isFlagEmoji(badge)) return undefined;
  return `https://streamed.pk/api/images/badge/${encodeURIComponent(badge)}.webp`;
}

function isNationalTeam(name: string) {
  return Boolean(countryKeyForTeam(name));
}

export interface TeamFlagDisplay {
  imageSrc?: string;
  emoji?: string;
  initials: string;
}

export function teamFlagDisplay(name: string, badge?: string): TeamFlagDisplay {
  const initials = (badge && badge.length <= 4 && !isFlagEmoji(badge) ? badge : name)
    .replace(/[^a-zA-Z]/g, "")
    .slice(0, 3)
    .toUpperCase() || name.slice(0, 2).toUpperCase();

  const emoji = badge && isFlagEmoji(badge) ? badge : undefined;
  const flagCdn = flagCdnSrc(name);
  const national = isNationalTeam(name);

  if (national) {
    if (flagCdn) return { imageSrc: flagCdn, emoji, initials };
    if (emoji) return { emoji, initials };
    return { initials };
  }

  // Clubs: prefer StreamEx/streamed crest tokens (same as iOS). Flags only for national sides.
  const crest = badge ? streamedBadgeSlugSrc(badge) : undefined;
  const imageSrc = crest ?? flagCdn;
  if (imageSrc) return { imageSrc, emoji, initials };
  if (emoji) return { emoji, initials };
  return { initials };
}
