// Owner decision (21 Nov 2026): catch fixture-feed problems before the owner
// does. Two independent checks feed the existing sports monitor:
//   1. the Worker's per-group refresh history (/api/sports/history), so a
//      failure between sparse scheduled runs is still seen;
//   2. ESPN's public scoreboard, so a match ESPN reports in play that Fotty's
//      feed does not show as live is flagged.
// Findings carry competition or source-group IDs and codes only.
import { sameTeamName } from "../web/workers/playback/src/sports-fixture-sources.mjs";

const MINUTE = 60_000;
export const HISTORY_WINDOW_MS = 120 * MINUTE;
export const ESPN_LEAGUES = Object.freeze({ "premier-league": "eng.1", "champions-league": "uefa.champions",
  "la-liga": "esp.1", "serie-a": "ita.1", "bundesliga": "ger.1", "ligue-1": "fra.1" });

/** History findings: a group that was unavailable inside the window. */
export function auditSportsHistory(body, { now = Date.now() } = {}) {
  const findings = [];
  if (!body || typeof body !== "object" || !body.sources || typeof body.sources !== "object") return findings;
  for (const [group, entries] of Object.entries(body.sources)) {
    if (!/^[a-z0-9-]{1,80}$/.test(group)) continue;
    if (!Array.isArray(entries)) { findings.push({ code: "history-unreadable", actionable: false, competitionId: group }); continue; }
    const recent = entries.filter((entry) => {
      const at = Date.parse(entry?.at);
      return Number.isFinite(at) && at <= now + 5 * MINUTE && now - at <= HISTORY_WINDOW_MS;
    });
    const failed = recent.filter((entry) => entry.outcome === "unavailable");
    if (!failed.length) continue;
    const latest = recent[recent.length - 1];
    // A single transient failure that already recovered is recorded but only
    // becomes actionable when it repeats or is still failing.
    findings.push({ code: "recent-lane-failure", competitionId: group,
      actionable: latest?.outcome === "unavailable" || failed.length >= 2 });
  }
  return findings;
}

function easternDay(now) {
  return new Date(now - 5 * 3_600 * 1000).toISOString().slice(0, 10).replaceAll("-", "");
}

/** ESPN reports in progress, Fotty's feed does not show it live 10+ minutes after kickoff. */
export async function collectESPNLiveMismatches(body, { now = Date.now(), fetchJSON } = {}) {
  const findings = [];
  if (!Array.isArray(body?.fixtures) || typeof fetchJSON !== "function") return findings;
  for (const [competitionId, slug] of Object.entries(ESPN_LEAGUES)) {
    const rows = body.fixtures.filter((row) => row?.competitionId === competitionId && row.eventKind === "match"
      && !["finished", "cancelled", "postponed"].includes(row.status)
      && Date.parse(row.start) <= now - 10 * MINUTE && Date.parse(row.start) >= now - 3 * 3_600_000);
    if (!rows.length) continue;
    let events;
    try {
      const data = await fetchJSON(`https://site.api.espn.com/apis/site/v2/sports/soccer/${slug}/scoreboard?dates=${easternDay(now)}`);
      if (data?.leagues?.[0]?.slug !== slug || !Array.isArray(data.events)) throw new Error("ESPN scoreboard invalid");
      events = data.events;
    } catch {
      findings.push({ code: "espn-comparison-unavailable", actionable: false, competitionId });
      continue;
    }
    for (const event of events) {
      const type = event?.status?.type;
      const competitors = event?.competitions?.[0]?.competitors;
      if (type?.state !== "in" || type.completed !== false || !Array.isArray(competitors)) continue;
      const side = (role) => competitors.find((item) => item?.homeAway === role)?.team;
      const home = side("home"), away = side("away"), kickoff = Date.parse(event.date);
      if (!home || !away || !Number.isFinite(kickoff)) continue;
      const names = (team) => [team.displayName, team.shortDisplayName, team.name].filter((name) => typeof name === "string");
      const matches = rows.filter((row) => {
        const ours = (role) => row.participants?.find((item) => item.role === role)?.name;
        return Math.abs(Date.parse(row.start) - kickoff) <= 5 * MINUTE && ours("home") && ours("away")
          && sameTeamName([ours("home")], names(home)) && sameTeamName([ours("away")], names(away));
      });
      if (matches.length === 1 && matches[0].status !== "live") {
        findings.push({ code: "espn-live-mismatch", actionable: true, competitionId });
        break;
      }
    }
  }
  return findings;
}
