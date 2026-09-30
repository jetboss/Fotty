import { abortable, boundedJSON, coachDeadline } from "./coach-safety.mjs";
import { admitICC, CRICKET_COMPETITIONS, iccScheduleURL, nextCricketRefresh, normalizeICC,
  parseICCPage, validateCricketSnapshot } from "./cricket-fixture-policy.mjs";
import cplFallback from "../../../public/data/cpl-2026-fixtures.json" with { type: "json" };
import { validateCPLManifest } from "./cpl-fixture-policy.mjs";

const STATE_KEY = "cricket-registry-v1";
const MINUTE = 60_000;

export async function collectICC(now, fetchImpl = fetch) {
  const deadline = coachDeadline(undefined, 12_000);
  try {
    const pages = [];
    for (let page = 1; page <= 3; page++) {
      const response = await abortable(() => fetchImpl(iccScheduleURL(now, page), {
        signal: deadline.signal, headers: { Accept: "application/json", "User-Agent": "Fotty fixture service/1.0" },
        cf: { cacheEverything: true, cacheTtl: 60 },
      }), deadline.signal);
      if (!response.ok) throw new Error("ICC upstream unavailable");
      pages.push(parseICCPage(await boundedJSON(response, 2_000_000, deadline.signal), now));
      if (pages.reduce((sum, p) => sum + p.rows.length, 0) >= pages[0].count) return normalizeICC(pages, now);
      if (!pages[pages.length - 1].rows.length) throw new Error("ICC pagination incomplete");
    }
    throw new Error("ICC pagination exceeded bound");
  } finally { deadline.dispose(); }
}

function publicCoverage(id, fixtures, checkedAt, available, pendingFixtureCount = 0) {
  const comp = CRICKET_COMPETITIONS.find((c) => c.id === id);
  const rows = fixtures.filter((f) => f.competitionId === id);
  return { competitionId: id, competitionName: comp.name, status: available ? "covered" : "unavailable",
    checkedAt, fixtureCount: rows.length, expectedFixtureCount: rows.length, pendingFixtureCount,
    ...(rows.filter((f) => f.status === "scheduled").map((f) => f.start).sort()[0]
      ? { nextStart: rows.filter((f) => f.status === "scheduled").map((f) => f.start).sort()[0] } : {}) };
}

function cplCoverage(now) {
  // CPL continues through its existing full-season verified adapter. This
  // international snapshot does not compete with that authority or infer live.
  const ends = cplFallback.fixtures?.map((f) => Date.parse(f.start || f.startAt || f.startTime || f.kickoffUTC)).filter(Number.isFinite) || [];
  const last = ends.length ? Math.max(...ends) : NaN;
  const knownSeason = Number(cplFallback.season);
  const offseason = now.getUTCFullYear() === knownSeason && Number.isFinite(last) && now.getTime() > last + 2 * 86_400_000;
  return { competitionId: "cpl", competitionName: "Caribbean Premier League",
    status: offseason ? "offseason" : "unavailable", checkedAt: offseason ? now.toISOString() : cplFallback.checkedAt,
    fixtureCount: 0, expectedFixtureCount: 0 };
}

const CPL_TEAMS = { antigua: "Antigua & Barbuda Falcons", barbados: "Barbados Tridents", guyana: "Guyana Amazon Warriors",
  jamaica: "Jamaica Kingsmen", saintLucia: "Saint Lucia Kings", stKitts: "St Kitts & Nevis Patriots", trinbago: "Trinbago Knight Riders" };

async function currentCPL(now, previous, collect) {
  const empty = cplCoverage(now);
  if (empty.status === "offseason") return { fixtures: [], coverage: empty };
  try {
    if (!collect) throw new Error("CPL authority unavailable");
    const response = await collect();
    const manifest = await boundedJSON(response, 128 * 1024);
    validateCPLManifest(manifest);
    if (!response.ok || !["verified", "live-verified"].includes(manifest.sourceStatus)
      || Math.abs(now.getTime() - Date.parse(manifest.checkedAt)) > 30 * MINUTE) throw new Error("CPL receipt unavailable");
    const fixtures = manifest.fixtures.filter((f) => f.team1 && f.team2).map((f) => ({
      id: `cpl:${manifest.season}:${f.number}`, start: new Date(f.start).toISOString(), format: "T20",
      // A schedule and a stream are not official live-state evidence.
      status: Date.parse(f.start) < now.getTime() ? "unknown" : "scheduled",
      competitionId: "cpl", competitionName: "Caribbean Premier League",
      home: { id: `cpl:${f.team1}`, name: manifest.teamNames?.[f.team1] || CPL_TEAMS[f.team1] },
      away: { id: `cpl:${f.team2}`, name: manifest.teamNames?.[f.team2] || CPL_TEAMS[f.team2] },
      source: { name: "CPL", url: manifest.sources[0].url, observedAt: manifest.checkedAt },
    }));
    return { fixtures, coverage: publicCoverage("cpl", fixtures, manifest.checkedAt, true) };
  } catch {
    const fixtures = previous?.fixtures.filter((f) => f.competitionId === "cpl") || [];
    const oldCoverage = previous?.coverage.find((c) => c.competitionId === "cpl");
    return { fixtures, coverage: { ...(oldCoverage || empty), status: "unavailable" } };
  }
}

async function revisionFor(fixtures) {
  const content = fixtures.map((f) => ({ ...f, source: { name: f.source.name, url: f.source.url } }));
  const bytes = new TextEncoder().encode(JSON.stringify(content));
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)))
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function refreshCricketState(previous, now, collect = collectICC, collectCPL) {
  const old = previous?.snapshot;
  // Independent authorities run under separate bounded requests. A slow CPL
  // verifier must not consume the international feed's cold-start budget.
  const cplPromise = currentCPL(now, old, collectCPL);
  let accepted;
  try { accepted = admitICC(await collect(now), old?.fixtures, now); }
  catch {
    const cpl = await cplPromise;
    // Retained receipts are immutable on failure. No successful-looking empty
    // catalog, refreshed live flag, or exception text is emitted to customers.
    const failures = (previous?.consecutiveFailures || 0) + 1;
    if (!old) {
      const state = { consecutiveFailures: failures, lastAttemptAt: now.toISOString(),
        nextAttemptAt: new Date(now.getTime() + 5 * MINUTE).toISOString() };
      if (!cpl.fixtures.length || cpl.coverage.status !== "covered") return state;
      state.snapshot = validateCricketSnapshot({ schemaVersion: 1, complete: true, checkedAt: cpl.coverage.checkedAt,
        revision: await revisionFor(cpl.fixtures), sourceStatus: "partial", fixtures: cpl.fixtures,
        coverage: [cpl.coverage, ...["west-indies", "icc"].map((id) => publicCoverage(id, [], "1970-01-01T00:00:00.000Z", false))],
        sync: { consecutiveFailures: failures, lastAttemptAt: now.toISOString() } });
      return state;
    }
    const coverage = old.coverage.map((c) => c.competitionId === "cpl" ? cpl.coverage : { ...c, status: "unavailable" });
    const fixtures = [...old.fixtures.filter((f) => f.competitionId !== "cpl"), ...cpl.fixtures]
      .sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
    return { ...previous, consecutiveFailures: failures, lastAttemptAt: now.toISOString(),
      nextAttemptAt: new Date(now.getTime() + 5 * MINUTE).toISOString(),
      snapshot: { ...old, fixtures, revision: await revisionFor(fixtures), coverage,
        checkedAt: [old.checkedAt, ...fixtures.map((f) => f.source.observedAt)].sort().at(-1), sourceStatus: "last-known-good",
        sync: { consecutiveFailures: failures, lastAttemptAt: now.toISOString(), lastSuccessAt: previous.lastSuccessAt } } };
  }
  const cpl = await cplPromise;
  const fixtures = [...accepted.fixtures, ...cpl.fixtures].sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  const coverage = [cpl.coverage, ...["west-indies", "icc"].map((id) => publicCoverage(id, fixtures, accepted.observedAt, true, accepted.pendingByCompetition?.[id]))];
  const allCovered = coverage.every((c) => c.status !== "unavailable");
  const snapshot = validateCricketSnapshot({ schemaVersion: 1, complete: true,
    checkedAt: [accepted.observedAt, ...fixtures.map((f) => f.source.observedAt)].sort().at(-1),
    revision: await revisionFor(fixtures), sourceStatus: allCovered ? "verified" : "partial", fixtures, coverage,
    sync: { consecutiveFailures: 0, lastAttemptAt: now.toISOString(), lastSuccessAt: now.toISOString() } });
  return { snapshot, consecutiveFailures: 0, lastAttemptAt: now.toISOString(), lastSuccessAt: now.toISOString(),
    nextAttemptAt: new Date(now.getTime() + nextCricketRefresh(fixtures, now)).toISOString() };
}

export class CricketFixtureRegistry {
  constructor(state, env, options = {}) { this.state = state; this.env = env; this.options = options; this.queue = Promise.resolve(); }

  enqueue(operation) {
    const result = this.queue.then(operation);
    this.queue = result.then(() => undefined, () => undefined);
    return result;
  }

  async refresh() {
    const now = new Date();
    const previous = await this.state.storage.get(STATE_KEY);
    if (previous && Date.parse(previous.nextAttemptAt) > now.getTime()) return previous;
    const next = await refreshCricketState(previous, now, this.options.collectICC || collectICC, this.options.collectCPL);
    // Persist before readers see an accepted revision; cron and cold callers
    // share this one object, so they cannot amplify upstream refresh traffic.
    await this.state.storage.put(STATE_KEY, next);
    console.log(JSON.stringify({ event: "cricket_fixture_refresh", outcome: next.snapshot?.sourceStatus || "unavailable",
      count: next.snapshot?.fixtures.length || 0, consecutiveFailures: next.consecutiveFailures }));
    return next;
  }

  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (request.method === "POST" && path === "/refresh") {
      const current = await this.enqueue(() => this.refresh());
      return Response.json({ status: current.snapshot?.sourceStatus || "unavailable", nextAttemptAt: current.nextAttemptAt });
    }
    if (request.method !== "GET" || path !== "/fixtures") return Response.json({ error: "Not found" }, { status: 404 });
    let current = await this.state.storage.get(STATE_KEY);
    if (!current) current = await this.enqueue(() => this.refresh());
    else if (Date.parse(current.nextAttemptAt) <= Date.now()) this.state.waitUntil(this.enqueue(() => this.refresh()));
    if (!current?.snapshot) return Response.json({ schemaVersion: 1, complete: false, sourceStatus: "unavailable",
      sync: { consecutiveFailures: current?.consecutiveFailures || 0, lastAttemptAt: current?.lastAttemptAt } }, { status: 503 });
    return Response.json(current.snapshot);
  }
}
