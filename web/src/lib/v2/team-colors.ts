// Shared preset colors for major football clubs and national sides.
export const TEAM_COLORS: Record<string, { primary: string; secondary: string }> = {
  // National sides
  "argentina": { primary: "#74acdf", secondary: "#ffffff" },
  "egypt": { primary: "#ce1126", secondary: "#000000" },
  "switzerland": { primary: "#da291c", secondary: "#ffffff" },
  "colombia": { primary: "#fcd116", secondary: "#003893" },
  "france": { primary: "#002395", secondary: "#ffffff" },
  "morocco": { primary: "#c1272d", secondary: "#006233" },
  "mexico": { primary: "#006847", secondary: "#ce1126" },
  "south africa": { primary: "#007a4d", secondary: "#ffb612" },
  "south korea": { primary: "#cd1125", secondary: "#0a1b3a" },
  "korea": { primary: "#cd1125", secondary: "#0a1b3a" },
  "czech": { primary: "#11457e", secondary: "#d90f17" },
  "canada": { primary: "#ff0000", secondary: "#ffffff" },
  "bosnia": { primary: "#002f6c", secondary: "#febd11" },
  "usa": { primary: "#002868", secondary: "#bf0a30" },
  "united states": { primary: "#002868", secondary: "#bf0a30" },
  "netherlands": { primary: "#ff4f00", secondary: "#002147" },
  "belgium": { primary: "#e30613", secondary: "#ffd919" },
  "brazil": { primary: "#ffdf00", secondary: "#009b3a" },
  "germany": { primary: "#ffffff", secondary: "#d90000" },
  "england": { primary: "#ce1124", secondary: "#ffffff" },
  "italy": { primary: "#113a5d", secondary: "#008c45" },
  "spain": { primary: "#c60b1e", secondary: "#ffc400" },
  "portugal": { primary: "#ff0000", secondary: "#006600" },
  "croatia": { primary: "#ff0000", secondary: "#002f6c" },
  "uruguay": { primary: "#0081c6", secondary: "#ffffff" },
  "japan": { primary: "#bc002d", secondary: "#002f6c" },
  "australia": { primary: "#00008b", secondary: "#ffd700" },

  // Clubs
  "arsenal": { primary: "#ef0107", secondary: "#063672" },
  "chelsea": { primary: "#034694", secondary: "#ee242c" },
  "barcelona": { primary: "#004d98", secondary: "#a50044" },
  "real madrid": { primary: "#8a9bb8", secondary: "#121f4c" },
  "liverpool": { primary: "#c8102e", secondary: "#f6eb61" },
  "manchester united": { primary: "#da291c", secondary: "#000000" },
  "manchester city": { primary: "#6cabdd", secondary: "#1c2c5b" },
  "bayern munich": { primary: "#dc052d", secondary: "#0066b2" },
  "juventus": { primary: "#7d7d7d", secondary: "#000000" },
  "inter milan": { primary: "#0068a8", secondary: "#221f1f" },
  "tottenham": { primary: "#132257", secondary: "#ffffff" },
  "paris saint-germain": { primary: "#002F6C", secondary: "#E30613" },
  "psg": { primary: "#002F6C", secondary: "#E30613" },
  "dortmund": { primary: "#FDE100", secondary: "#000000" },
  "milan": { primary: "#E30613", secondary: "#000000" },
  "ac milan": { primary: "#E30613", secondary: "#000000" },
  "atletico madrid": { primary: "#CB3524", secondary: "#192C5B" },
  "ajax": { primary: "#D2122E", secondary: "#ffffff" },
};

export function resolveTeamColor(teamName?: string): string | null {
  if (!teamName) return null;
  const name = teamName.toLowerCase().trim();
  for (const [key, colors] of Object.entries(TEAM_COLORS)) {
    if (name.includes(key)) return colors.primary;
  }
  return null;
}
