/**
 * Fotty playback edge API — iOS parity for getfotty.com static FTP.
 *
 * Routes:
 *   GET /api/live/streams?source=&id=
 *   GET /api/embed/player?source=&id=&streamNo=
 *   GET /api/cricket/cpl-fixtures
 *   GET /api/cricket/fixtures
 *   GET /api/sports/fixtures
 *   GET /health
 *
 * Browser playback stays on the provider origin. Fotty does not mirror or
 * sanitize provider HTML/media into a first-party response.
 */

import {
  deterministicFplScoringResponse,
  isFplScoringQuestion,
  resolveFplScoring,
} from "./fpl-scoring.mjs";
import { checkCoachLimit, readCoachRequest } from "./coach-request.mjs";
import { abortable, authorizePaidCoach, boundedJSON, boundedText, coachDeadline, reservePaidCoach } from "./coach-safety.mjs";
import { resolveCoachPlayers, coachPlayerClarification, collectCoachPlayerHistory, coachContextConflicts } from "./coach-evidence.mjs";
import { coachTransferContext, validateCoachTransfers } from "./coach-transfers.mjs";
import { WORKER_SOURCE_VERSION } from "./worker-version.mjs";
export { CoachQuotaBudget } from "./coach-safety.mjs";
import cplFixtureFallback from "../../../public/data/cpl-2026-fixtures.json" with { type: "json" };
import { cplFixtureSources, resolveCPLManifest, validateCPLManifest } from "./cpl-fixture-policy.mjs";
import { CricketFixtureRegistry as BaseCricketFixtureRegistry } from "./cricket-fixture-registry.mjs";
import { SPORTS_SOURCES, collectSportsSource } from "./sports-fixture-sources.mjs";
import { SPORTS_EVENT_SOURCES, collectSportsEventSource } from "./sports-fixture-event-sources.mjs";
import { SportsFixtureRegistry as BaseSportsFixtureRegistry, assembleSportsSnapshot } from "./sports-fixture-registry.mjs";

const ALL_SPORTS_SOURCES = [...SPORTS_SOURCES, ...SPORTS_EVENT_SOURCES];
const PRIMARY_SPORTS_SOURCE_IDS = new Set(SPORTS_SOURCES.map((source) => source.id));
function effectiveSportsSources(env) {
  return ALL_SPORTS_SOURCES.map((source) => source.publicUndocumented && env.FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED !== "1"
    ? { ...source, supported: false, reason: "This public website feed is awaiting separate source-access review." } : source);
}
export class SportsFixtureRegistry extends BaseSportsFixtureRegistry {
  constructor(state, env) {
    super(state, env, { descriptors: effectiveSportsSources(env), collect: (source, now, environment) =>
      PRIMARY_SPORTS_SOURCE_IDS.has(source.id) ? collectSportsSource(source, now, environment) : collectSportsEventSource(source, now, environment) });
  }
}

function sportsFixturesEnabled(env) { return Boolean(env.SPORTS_FIXTURES) && env.FOTTY_SPORTS_FIXTURES_ENABLED === "1"; }
function sportsRegistryStub(env, source) {
  return env.SPORTS_FIXTURES.get(env.SPORTS_FIXTURES.idFromName(`shared-sports-fixtures-v1:${source.id}`));
}
function sportsRegistryRequest(source, refresh = false) {
  return new Request(`https://sports-registry.invalid/${refresh ? "refresh" : "fixtures"}?source=${encodeURIComponent(source.id)}`,
    { method: refresh ? "POST" : "GET" });
}

async function mapSportsSources(operation, sources = ALL_SPORTS_SOURCES) {
  const results = [];
  // Bounded fanout on the shared Mac, edge, and source publishers alike.
  for (let index = 0; index < sources.length; index += 4) {
    results.push(...await Promise.all(sources.slice(index, index + 4).map(operation)));
  }
  return results;
}

async function handleSportsFixtures(env) {
  if (!sportsFixturesEnabled(env)) return json({ schemaVersion: 1, complete: false, sourceStatus: "unavailable", activation: "pending" }, 503);
  const deadline = coachDeadline(undefined, 12_000);
  try {
    const sources = effectiveSportsSources(env);
    const pairs = await mapSportsSources(async (source) => {
      if (source.supported === false) return [source.id, undefined];
      try {
        const state = await withDeadline(1_500, async (signal) => {
          const response = await abortable(() => sportsRegistryStub(env, source).fetch(sportsRegistryRequest(source)), signal);
          if (!response.ok) throw new Error("Sports registry unavailable");
          return boundedJSON(response, 1024 * 1024, signal);
        }, deadline.signal);
        return [source.id, state];
      } catch { return [source.id, { consecutiveFailures: 1 }]; }
    }, sources);
    const snapshot = await assembleSportsSnapshot(sources, new Map(pairs), new Date());
    const body = JSON.stringify(snapshot);
    if (new TextEncoder().encode(body).byteLength > 2 * 1024 * 1024) throw new Error("Sports snapshot exceeded bound");
    if (!snapshot.coverage.some((row) => row.status === "covered")) return json({ schemaVersion: 1, complete: false,
      sourceStatus: "unavailable", activation: "warming", coverage: snapshot.coverage }, 503);
    return new Response(body, { headers: corsHeaders({ "Content-Type": "application/json", "Cache-Control": "public, max-age=60" }) });
  } catch { return json({ schemaVersion: 1, complete: false, sourceStatus: "unavailable" }, 503); }
  finally { deadline.dispose(); }
}

export class CricketFixtureRegistry extends BaseCricketFixtureRegistry {
  constructor(state, env) { super(state, env, { collectCPL: () => handleCPLFixtures(env) }); }
}

function cricketRegistryStub(env) {
  return env.CRICKET_FIXTURES.get(env.CRICKET_FIXTURES.idFromName("shared-cricket-fixtures-v1"));
}

async function handleCricketFixtures(env) {
  if (!env.CRICKET_FIXTURES) return json({ schemaVersion: 1, complete: false, sourceStatus: "unavailable" }, 503);
  try {
    const response = await cricketRegistryStub(env).fetch("https://cricket-registry.invalid/fixtures");
    return new Response(response.body, { status: response.status, headers: corsHeaders({
      "Content-Type": "application/json", "Cache-Control": "public, max-age=60",
    }) });
  } catch {
    return json({ schemaVersion: 1, complete: false, sourceStatus: "unavailable" }, 503);
  }
}

const IOS_SAFARI_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

const EMBED_ST_ORIGIN = "https://embed.st";

/** Prefer StreamEx `delta` on web (echo PPV ids often 404 in-browser). */
const SOURCE_PRIORITY = ["delta", "hotel", "echo", "india", "golf", "alpha"];

const STREAM_PROVIDERS = [
  { label: "StreameX", baseURL: "https://www.streamex.net", pathPrefix: "/api/live/stream" },
  { label: "StreameX Mirror", baseURL: "https://streamex.sh", pathPrefix: "/api/live/stream" },
  { label: "Streamed Backup", baseURL: "https://streamed.pk", pathPrefix: "/api/stream" },
];

const FOOTBALL_DATA_ORIGIN = "https://api.football-data.org/v4";
const API_FOOTBALL_ORIGIN = "https://v3.football.api-sports.io";
// Keep Worker quota aligned with the iOS policy. Add "2" when Champions League
// live scores are enabled; API-Football accepts hyphen-separated league ids.
const ACTIVE_LIVE_SCORE_LEAGUE_IDS = ["39"];
const API_FOOTBALL_LIVE_FILTER = ACTIVE_LIVE_SCORE_LEAGUE_IDS.join("-");
const API_FOOTBALL_DAILY_CALL_BUDGET = 80;
const API_FOOTBALL_PROVIDER_RESERVE = 20;
const API_FOOTBALL_CACHE_TTL_MS = 240 * 1000;
const API_FOOTBALL_ACCESS_RETRY_MS = 4 * 60 * 60 * 1000;
const API_FOOTBALL_QUOTA_STATE_KEY = "premier-league-live-v1";
const STREAM_CATALOG_TIMEOUT_MS = 6_500;
const FIXTURE_SOURCE_TIMEOUT_MS = 8_000;
const FOOTBALL_SOURCE_TIMEOUT_MS = 8_000;
const SAFE_FOOTBALL_QUERY_VALUE = /^[A-Za-z0-9_,.-]+$/;
const FOOTBALL_MATCH_QUERY_KEYS = new Set([
  "dateFrom",
  "dateTo",
  "status",
  "limit",
  "competition",
  "season",
]);

function corsHeaders(extra = {}) {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Accept, Authorization, Content-Type, X-Fotty-Watch-Token, X-Fotty-Install-ID",
    "Access-Control-Expose-Headers": "Retry-After, X-Fotty-Catalog-Attempted, X-Fotty-Catalog-Coverage, X-Fotty-Catalog-Responding, X-Fotty-Fixture-Source, X-Fotty-Worker-Version",
    "Cache-Control": "no-store",
    "X-Fotty-Worker-Version": WORKER_SOURCE_VERSION,
    ...extra,
  };
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders({ "Content-Type": "application/json", ...extraHeaders }),
  });
}

function errorKind(error) {
  return error instanceof Error && error.name ? error.name : "Error";
}

function logWorkerEvent(level, event, details = {}) {
  const payload = JSON.stringify({ event, sourceVersion: WORKER_SOURCE_VERSION, ...details });
  if (level === "error") console.error(payload);
  else if (level === "warn") console.warn(payload);
  else console.log(payload);
}

async function withDeadline(milliseconds, operation, parentSignal) {
  const deadline = coachDeadline(parentSignal, milliseconds);
  try {
    return await abortable(() => operation(deadline.signal), deadline.signal);
  } finally {
    deadline.dispose();
  }
}

async function reviewedCPLFallback(env, requestOptions) {
  const rawURL = String(env.CPL_REVIEWED_MANIFEST_URL || "").trim();
  if (!rawURL) return cplFixtureFallback;
  try {
    const url = new URL(rawURL);
    if (url.protocol !== "https:" || url.username || url.password) return cplFixtureFallback;
    return await withDeadline(FIXTURE_SOURCE_TIMEOUT_MS, async (signal) => {
      const response = await fetch(url, {
        ...requestOptions,
        headers: { ...requestOptions.headers, Accept: "application/json" },
        signal,
      });
      if (!response.ok) throw new Error(`Reviewed manifest returned ${response.status}`);
      const manifest = await boundedJSON(response, 128 * 1024, signal);
      validateCPLManifest(manifest);
      return manifest;
    });
  } catch (error) {
    logWorkerEvent("warn", "cpl_reviewed_manifest_fallback", { outcome: "bundled", errorKind: errorKind(error) });
    return cplFixtureFallback;
  }
}

async function handleCPLFixtures(env) {
  const requestOptions = {
    headers: { "User-Agent": "Fotty fixture service/1.0" },
    cf: { cacheEverything: true, cacheTtl: 900 },
  };
  const fallback = await reviewedCPLFallback(env, requestOptions);
  try {
    const [verifierHTML, publishedHTML, correctionJSON] = await Promise.all([
      withDeadline(FIXTURE_SOURCE_TIMEOUT_MS, async (signal) => {
        const response = await fetch(cplFixtureSources.live, {
          ...requestOptions, headers: { ...requestOptions.headers, Accept: "text/html" }, signal,
        });
        if (!response.ok) throw new Error(`CPL verifier returned ${response.status}`);
        return boundedText(response, 5_000_000, signal);
      }),
      withDeadline(FIXTURE_SOURCE_TIMEOUT_MS, async (signal) => {
        const response = await fetch(cplFixtureSources.published, {
          ...requestOptions, headers: { ...requestOptions.headers, Accept: "text/html" }, signal,
        });
        if (!response.ok) throw new Error(`CPL schedule returned ${response.status}`);
        return boundedText(response, 1_000_000, signal);
      }),
      withDeadline(FIXTURE_SOURCE_TIMEOUT_MS, async (signal) => {
        const response = await fetch(cplFixtureSources.correction, {
          ...requestOptions, headers: { ...requestOptions.headers, Accept: "application/json" }, signal,
        });
        if (!response.ok) throw new Error(`CPL correction feed returned ${response.status}`);
        return boundedJSON(response, 256 * 1024, signal);
      }),
    ]);
    const resolved = resolveCPLManifest({
      fallback,
      verifierHTML,
      publishedHTML,
      correctionJSON,
    });
    const liveVerifiedChanges = resolved.authoritativeChanges.map(
      (change) => `Live-verified official change: ${change.message}. Durable fallback review is pending.`,
    );
    const sourceStatus = liveVerifiedChanges.length > 0 ? "live-verified" : "verified";
    return json({
      ...resolved.manifest,
      sourceStatus,
      warnings: [
        ...resolved.reviewedVerifierChanges.map((change) => change.message),
        ...liveVerifiedChanges,
      ],
    }, 200, {
      "Cache-Control": "public, max-age=300, stale-while-revalidate=300, stale-if-error=86400",
      "X-Fotty-Fixture-Source": sourceStatus,
    });
  } catch (error) {
    // A partial feed, parser change or new source conflict cannot erase the
    // reviewed schedule. Clients receive the complete bundled fallback.
    logWorkerEvent("warn", "cpl_verification_fallback", {
      outcome: "last-known-good",
      errorKind: errorKind(error),
      fallbackRevision: fallback.revision,
    });
    return json({
      ...fallback,
      sourceStatus: "last-known-good",
      warnings: ["Current schedule verification was unavailable; using the last reviewed CPL schedule."],
    }, 200, {
      "Cache-Control": "public, max-age=60, stale-while-revalidate=60, stale-if-error=86400",
      "X-Fotty-Fixture-Source": "last-known-good",
    });
  }
}

async function handleFootballDataMatches(url, env) {
  if (!env.FOOTBALL_DATA_API_KEY) {
    return json({ error: "Football scores are not configured." }, 503);
  }

  const competition = (url.searchParams.get("competition") || "").trim().toUpperCase();
  if (competition && !SAFE_FOOTBALL_QUERY_VALUE.test(competition)) {
    return json({ error: "Invalid competition." }, 400);
  }

  const upstream = new URL(
    competition
      ? `${FOOTBALL_DATA_ORIGIN}/competitions/${encodeURIComponent(competition)}/matches`
      : `${FOOTBALL_DATA_ORIGIN}/matches`
  );
  for (const [key, value] of url.searchParams.entries()) {
    if (!FOOTBALL_MATCH_QUERY_KEYS.has(key) || key === "competition") continue;
    const trimmed = value.trim();
    if (!trimmed || !SAFE_FOOTBALL_QUERY_VALUE.test(trimmed)) {
      return json({ error: `Invalid ${key}.` }, 400);
    }
    upstream.searchParams.set(key, trimmed);
  }

  const isLiveQuery = (upstream.searchParams.get("status") || "")
    .split(",")
    .some((value) => value === "IN_PLAY" || value === "PAUSED");
  try {
    const result = await withDeadline(FOOTBALL_SOURCE_TIMEOUT_MS, async (signal) => {
      const response = await fetch(upstream, {
        headers: {
          Accept: "application/json",
          "X-Auth-Token": env.FOOTBALL_DATA_API_KEY,
        },
        cf: { cacheEverything: true, cacheTtl: isLiveQuery ? 120 : 900 },
        signal,
      });
      if (!response.ok) return { ok: false, status: response.status };
      return { ok: true, status: response.status, body: await boundedText(response, 8 * 1024 * 1024, signal) };
    });
    if (!result.ok) {
      logWorkerEvent("warn", "football_schedule_upstream", { outcome: "error", status: result.status });
      return json({ error: "The football score provider is temporarily unavailable." }, result.status === 429 ? 429 : 502);
    }
    return new Response(result.body, {
      status: 200,
      headers: corsHeaders({
        "Content-Type": "application/json",
        "Cache-Control": isLiveQuery
          ? "public, max-age=60, stale-while-revalidate=60, stale-if-error=600"
          : "public, max-age=300, stale-while-revalidate=300, stale-if-error=3600",
      }),
    });
  } catch (error) {
    logWorkerEvent("error", "football_schedule_upstream", { outcome: "request-failed", errorKind: errorKind(error) });
    return json({ error: "The football score request failed." }, 502);
  }
}

function utcDayKey(timestamp) {
  return new Date(timestamp).toISOString().slice(0, 10);
}

function nextUTCDay(timestamp) {
  const date = new Date(timestamp);
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1);
}

function integerHeader(headers, name) {
  const raw = headers.get(name);
  if (raw === null) return null;
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? value : null;
}

function responseSnapshot(body, status, headers = {}) {
  const encodedBody = typeof body === "string" ? new TextEncoder().encode(body).buffer : body;
  return { body: encodedBody, status, headers };
}

function jsonSnapshot(data, status, headers = {}) {
  return responseSnapshot(JSON.stringify(data), status, {
    "Content-Type": "application/json",
    ...headers,
  });
}

function responseFromSnapshot(snapshot) {
  return new Response(snapshot.body.slice(0), {
    status: snapshot.status,
    headers: corsHeaders(snapshot.headers),
  });
}

function quotaHeaders(state, cacheStatus) {
  return {
    "X-Fotty-Live-Source": "api-football",
    "X-Fotty-Live-Cache": cacheStatus,
    "X-Fotty-Quota-Used": String(state.used || 0),
    "X-Fotty-Quota-Budget": String(API_FOOTBALL_DAILY_CALL_BUDGET),
    ...(Number.isFinite(state.providerRemaining)
      ? { "X-Fotty-Provider-Remaining": String(state.providerRemaining) }
      : {}),
    ...(Number.isFinite(state.providerLimit)
      ? { "X-Fotty-Provider-Limit": String(state.providerLimit) }
      : {}),
  };
}

function apiFootballLiveUpstreamURL() {
  const upstream = new URL(`${API_FOOTBALL_ORIGIN}/fixtures`);
  if (ACTIVE_LIVE_SCORE_LEAGUE_IDS.length === 1) {
    // API-Football rejects a lone id in `live` and rejects combining `live=all`
    // with a league. Query the current UTC match day and retain live statuses.
    const now = new Date();
    const season = now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1;
    upstream.searchParams.set("league", ACTIVE_LIVE_SCORE_LEAGUE_IDS[0]);
    upstream.searchParams.set("season", String(season));
    upstream.searchParams.set("date", utcDayKey(now));
  } else {
    upstream.searchParams.set("live", API_FOOTBALL_LIVE_FILTER);
  }
  return upstream;
}

const API_FOOTBALL_LIVE_STATUSES = new Set(["1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE"]);

function apiFootballPayloadError(body) {
  try {
    const text = typeof body === "string" ? body : new TextDecoder().decode(body);
    const payload = JSON.parse(text);
    if (!payload || !Array.isArray(payload.response)) return "Missing response array.";

    const errors = payload.errors;
    if (Array.isArray(errors)) return errors.length > 0 ? errors.join("; ") : null;
    if (errors && typeof errors === "object") {
      const messages = Object.values(errors).filter((value) => String(value).trim().length > 0);
      return messages.length > 0 ? messages.join("; ") : null;
    }
    return typeof errors === "string" && errors.trim() ? errors : null;
  } catch {
    return "Malformed provider response.";
  }
}

function normalizedAPIFootballLiveBody(body) {
  const payload = JSON.parse(body);
  if (ACTIVE_LIVE_SCORE_LEAGUE_IDS.length !== 1) return body;
  const response = payload.response.filter((fixture) =>
    API_FOOTBALL_LIVE_STATUSES.has(String(fixture?.fixture?.status?.short || "").toUpperCase())
  );
  return JSON.stringify({ ...payload, results: response.length, response });
}

/**
 * One named Durable Object serializes and caches the tiny Premier League feed.
 * This prevents separate Cloudflare locations from each spending the upstream
 * allowance and keeps 20 provider calls in reserve for operator recovery.
 */
export class FootballQuotaBudget {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.liveRequestInFlight = null;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/status") {
      const state = await this.loadState(Date.now());
      return json({
        configured: Boolean(this.env.API_FOOTBALL_KEY),
        competitionIds: ACTIVE_LIVE_SCORE_LEAGUE_IDS,
        used: state.used,
        budget: API_FOOTBALL_DAILY_CALL_BUDGET,
        providerRemaining: state.providerRemaining,
        providerLimit: state.providerLimit,
        cacheAgeSeconds: state.cachedAt ? Math.max(0, Math.floor((Date.now() - state.cachedAt) / 1000)) : null,
        reserveActive: this.reserveIsActive(state, Date.now()),
        accessRestricted: Number.isFinite(state.accessBlockedUntil) && Date.now() < state.accessBlockedUntil,
        accessRetryAt: Number.isFinite(state.accessBlockedUntil)
          ? new Date(state.accessBlockedUntil).toISOString()
          : null,
      });
    }
    if (url.pathname !== "/live") return json({ error: "Not found" }, 404);
    if (!this.env.API_FOOTBALL_KEY) {
      return json({ error: "Premier League live scores are not configured." }, 503);
    }

    let promise = this.liveRequestInFlight;
    if (!promise) {
      promise = this.fetchLiveSnapshot();
      this.liveRequestInFlight = promise;
    }
    try {
      return responseFromSnapshot(await promise);
    } finally {
      if (this.liveRequestInFlight === promise) this.liveRequestInFlight = null;
    }
  }

  async loadState(now) {
    const stored = (await this.state.storage.get(API_FOOTBALL_QUOTA_STATE_KEY)) || {};
    const day = utcDayKey(now);
    if (stored.day !== day) {
      stored.day = day;
      stored.used = 0;
    }
    if (this.reserveIsActive(stored, now) === false
        && Number.isFinite(stored.providerRemaining)
        && stored.providerRemaining <= API_FOOTBALL_PROVIDER_RESERVE) {
      stored.providerRemaining = null;
      stored.providerObservedAt = null;
    }
    if (Number.isFinite(stored.accessBlockedUntil) && now >= stored.accessBlockedUntil) {
      stored.accessBlockedUntil = null;
      stored.accessReason = null;
    }
    return stored;
  }

  reserveIsActive(state, now) {
    return Number.isFinite(state.providerRemaining)
      && state.providerRemaining <= API_FOOTBALL_PROVIDER_RESERVE
      && Number.isFinite(state.providerObservedAt)
      && now < state.providerObservedAt + 24 * 60 * 60 * 1000;
  }

  async fetchLiveSnapshot() {
    const now = Date.now();
    const state = await this.loadState(now);

    if (state.cachedBody && state.cachedAt && now - state.cachedAt < API_FOOTBALL_CACHE_TTL_MS) {
      if (!apiFootballPayloadError(state.cachedBody)) {
        return responseSnapshot(
          state.cachedBody,
          200,
          {
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=120",
            ...quotaHeaders(state, "hit"),
          }
        );
      }
      state.cachedBody = null;
      state.cachedAt = null;
    }

    if (Number.isFinite(state.accessBlockedUntil) && now < state.accessBlockedUntil) {
      return jsonSnapshot({
        error: "Current-season live scores are unavailable on the configured provider plan.",
        retryAt: new Date(state.accessBlockedUntil).toISOString(),
      }, 503, {
        ...quotaHeaders(state, "access-restricted"),
        "Retry-After": String(Math.max(60, Math.ceil((state.accessBlockedUntil - now) / 1000))),
      });
    }

    if (this.reserveIsActive(state, now)) {
      const retryAt = state.providerObservedAt + 24 * 60 * 60 * 1000;
      return jsonSnapshot({
        error: "Live-score allowance is being held in reserve.",
        retryAt: new Date(retryAt).toISOString(),
      }, 429, {
        ...quotaHeaders(state, "reserved"),
        "Retry-After": String(Math.max(60, Math.ceil((retryAt - now) / 1000))),
      });
    }

    if ((state.used || 0) >= API_FOOTBALL_DAILY_CALL_BUDGET) {
      const retryAt = nextUTCDay(now);
      return jsonSnapshot({
        error: "Fotty's daily live-score budget has been reached.",
        retryAt: new Date(retryAt).toISOString(),
      }, 429, {
        ...quotaHeaders(state, "budget-exhausted"),
        "Retry-After": String(Math.max(60, Math.ceil((retryAt - now) / 1000))),
      });
    }

    state.used = (state.used || 0) + 1;
    await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);

    try {
      const upstream = await withDeadline(FOOTBALL_SOURCE_TIMEOUT_MS, async (signal) => {
        const response = await fetch(apiFootballLiveUpstreamURL(), {
          headers: {
            Accept: "application/json",
            "x-apisports-key": this.env.API_FOOTBALL_KEY,
          },
          signal,
        });
        return {
          ok: response.ok,
          status: response.status,
          headers: new Headers(response.headers),
          body: await boundedText(response, 4 * 1024 * 1024, signal),
        };
      });

      state.providerRemaining = integerHeader(upstream.headers, "x-ratelimit-requests-remaining");
      state.providerLimit = integerHeader(upstream.headers, "x-ratelimit-requests-limit");
      state.providerObservedAt = now;

      if (!upstream.ok) {
        if (upstream.status === 429) state.providerRemaining = 0;
        await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);
        logWorkerEvent("warn", "football_live_upstream", { outcome: "error", status: upstream.status });
        return jsonSnapshot(
          { error: "The Premier League live-score provider is temporarily unavailable." },
          upstream.status === 429 ? 429 : 502,
          quotaHeaders(state, "upstream-error")
        );
      }

      const upstreamBody = upstream.body;
      const providerError = apiFootballPayloadError(upstreamBody);
      if (providerError) {
        logWorkerEvent("warn", "football_live_upstream", {
          outcome: "provider-rejected",
          accessRestricted: /do not have access to this season/i.test(providerError),
        });
        state.cachedBody = null;
        state.cachedAt = null;
        if (/do not have access to this season/i.test(providerError)) {
          state.accessBlockedUntil = now + API_FOOTBALL_ACCESS_RETRY_MS;
          state.accessReason = "current-season-unavailable";
        }
        await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);
        return jsonSnapshot(
          { error: "The Premier League live-score provider rejected the request." },
          502,
          quotaHeaders(state, "upstream-error")
        );
      }
      const body = normalizedAPIFootballLiveBody(upstreamBody);
      state.accessBlockedUntil = null;
      state.accessReason = null;
      state.cachedBody = body;
      state.cachedAt = now;
      await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);
      return responseSnapshot(body, 200, {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=120",
        ...quotaHeaders(state, "miss"),
      });
    } catch (error) {
      await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);
      logWorkerEvent("error", "football_live_upstream", { outcome: "request-failed", errorKind: errorKind(error) });
      return jsonSnapshot(
        { error: "The Premier League live-score request failed." },
        502,
        quotaHeaders(state, "network-error")
      );
    }
  }
}

function footballQuotaStub(env) {
  const id = env.FOOTBALL_SCORE_BUDGET.idFromName("premier-league-live");
  return env.FOOTBALL_SCORE_BUDGET.get(id);
}

async function handleAPIFootballLive(env) {
  return footballQuotaStub(env).fetch("https://fotty.internal/live");
}

async function handleHealth(env) {
  let liveScoreQuota = null;
  try {
    const response = await footballQuotaStub(env).fetch("https://fotty.internal/status");
    liveScoreQuota = await response.json();
  } catch {
    liveScoreQuota = { configured: Boolean(env.API_FOOTBALL_KEY), status: "unavailable" };
  }
  const apiFootballCredentialConfigured = Boolean(env.API_FOOTBALL_KEY);
  const currentSeasonLiveScoresAvailable = apiFootballCredentialConfigured
    && liveScoreQuota?.accessRestricted !== true;
  return json({
    ok: true,
    service: "fotty-playback",
    sourceVersion: WORKER_SOURCE_VERSION,
    footballScheduleConfigured: Boolean(env.FOOTBALL_DATA_API_KEY),
    liveScoreCompetitions: ["Premier League"],
    catalogProviderCount: STREAM_PROVIDERS.length,
    catalogCoverageMode: "parallel-with-direct-fallback",
    cplFallbackRevision: cplFixtureFallback.revision,
    cricketFixtureRegistryConfigured: Boolean(env.CRICKET_FIXTURES),
    cricketFixtureRefreshMode: "scheduled-adaptive",
    sportsFixtureRegistryConfigured: Boolean(env.SPORTS_FIXTURES),
    sportsFixtureServiceEnabled: sportsFixturesEnabled(env),
    sportsPublicWebFeedsEnabled: env.FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED === "1",
    sportsFixtureRefreshMode: "scheduled-per-source-adaptive",
    apiFootballCredentialConfigured,
    premierLeagueLiveScoresConfigured: currentSeasonLiveScoresAvailable,
    liveScoreQuota,
  });
}

function embedStPlayerUrl(source, id, streamNo) {
  return `${EMBED_ST_ORIGIN}/embed/${encodeURIComponent(source)}/${encodeURIComponent(id)}/${streamNo}`;
}

function sourceRank(source) {
  const index = SOURCE_PRIORITY.indexOf((source || "").toLowerCase());
  return index >= 0 ? index : 999;
}

function heatTierRank(value) {
  switch ((value || "").toLowerCase()) {
    case "veryhigh":
      return 0;
    case "high":
      return 1;
    case "medium":
      return 2;
    case "low":
      return 3;
    default:
      return 4;
  }
}

const APPROVED_PLAYBACK_EMBED_DOMAINS = [
  "embed.st", "embedhd.st", "exposestrat.com", "embedsports.top",
  "streamex.net", "streamex.sh", "streamed.pk", "streamed.su",
  "pooembed.eu", "score808live.tv", "strmd.st",
];

function isApprovedPlaybackEmbedURL(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return false;
    if (url.port && url.port !== "443") return false;
    const host = url.hostname.toLowerCase();
    return APPROVED_PLAYBACK_EMBED_DOMAINS.some(
      (domain) => host === domain || host.endsWith(`.${domain}`)
    );
  } catch {
    return false;
  }
}

async function fetchVariants(provider, source, id) {
  const startedAt = Date.now();
  try {
    return await withDeadline(STREAM_CATALOG_TIMEOUT_MS, async (signal) => {
      const response = await fetch(
        `${provider.baseURL}${provider.pathPrefix}/${encodeURIComponent(source)}/${encodeURIComponent(id)}`,
        {
          headers: {
            Accept: "application/json",
            Referer: provider.baseURL,
            "User-Agent": IOS_SAFARI_USER_AGENT,
          },
          signal,
        }
      );
      if (response.status === 404) {
        return { provider: provider.label, outcome: "empty", status: 404, elapsedMs: Date.now() - startedAt, variants: [] };
      }
      if (!response.ok) {
        return { provider: provider.label, outcome: "http-error", status: response.status, elapsedMs: Date.now() - startedAt, variants: [] };
      }
      const payload = await boundedJSON(response, 512 * 1024, signal);
      const rawVariants = Array.isArray(payload)
        ? payload
        : [payload?.streams, payload?.variants, payload?.data, payload?.result].find(Array.isArray);
      if (!Array.isArray(rawVariants)) {
        return { provider: provider.label, outcome: "malformed", status: response.status, elapsedMs: Date.now() - startedAt, variants: [] };
      }
      const variants = rawVariants.map((variant) => ({
        id: variant.id || id,
        source: variant.source || source,
        streamNo: variant.streamNo || 1,
        language: variant.language || "",
        hd: variant.hd === true,
        embedUrl: variant.embedUrl,
        viewers: Number(variant.viewers || 0),
        heatTier: variant.heatTier,
        provider: provider.label,
      }));
      return { provider: provider.label, outcome: variants.length ? "ok" : "empty", status: response.status,
        elapsedMs: Date.now() - startedAt, variants };
    });
  } catch (error) {
    return { provider: provider.label, outcome: "request-failed", errorKind: errorKind(error),
      elapsedMs: Date.now() - startedAt, variants: [] };
  }
}

async function handleStreams(url) {
  const source = url.searchParams.get("source")?.trim();
  const id = url.searchParams.get("id")?.trim();
  if (!source || !id) return json({ error: "Missing source or id" }, 400);

  const providerResults = await Promise.all(
    STREAM_PROVIDERS.map((provider) => fetchVariants(provider, source, id))
  );
  const responding = providerResults.filter((result) => result.outcome === "ok" || result.outcome === "empty").length;
  const coverage = responding === STREAM_PROVIDERS.length
    ? "complete"
    : responding > 0 ? "partial" : "fallback-only";
  const variants = providerResults
    .flatMap((result) => result.variants)
    .filter((variant) => isApprovedPlaybackEmbedURL(variant.embedUrl))
    .filter((variant, index, all) => all.findIndex((item) => item.embedUrl === variant.embedUrl) === index)
    .sort((a, b) => {
      const sourceDelta = sourceRank(a.source) - sourceRank(b.source);
      if (sourceDelta !== 0) return sourceDelta;
      const heatDelta = heatTierRank(a.heatTier) - heatTierRank(b.heatTier);
      if (heatDelta !== 0) return heatDelta;
      if (a.hd !== b.hd) return Number(b.hd) - Number(a.hd);
      if (a.viewers !== b.viewers) return b.viewers - a.viewers;
      return a.streamNo - b.streamNo;
    });

  if (variants.length === 0) {
    variants.push({
      id,
      source,
      streamNo: 1,
      language: "",
      hd: true,
      embedUrl: `https://embed.st/embed/${encodeURIComponent(source)}/${encodeURIComponent(id)}/1`,
      viewers: 0,
      heatTier: "legacy",
      provider: "Legacy",
    });
  }

  if (coverage !== "complete") {
    logWorkerEvent(responding > 0 ? "warn" : "error", "stream_catalog_coverage", {
      coverage,
      responding,
      attempted: STREAM_PROVIDERS.length,
      providers: providerResults.map(({ provider, outcome, status, elapsedMs, errorKind: providerErrorKind }) => ({
        provider, outcome, status: status || null, elapsedMs, errorKind: providerErrorKind || null,
      })),
    });
  }
  return json(variants, 200, {
    "Cache-Control": "public, max-age=15, stale-while-revalidate=15, stale-if-error=120",
    "X-Fotty-Catalog-Attempted": String(STREAM_PROVIDERS.length),
    "X-Fotty-Catalog-Coverage": coverage,
    "X-Fotty-Catalog-Responding": String(responding),
  });
}

async function handlePlayer(url) {
  const source = url.searchParams.get("source")?.trim();
  const id = url.searchParams.get("id")?.trim();
  const streamNo = Number(url.searchParams.get("streamNo") || "1");
  if (!source || !id || !Number.isFinite(streamNo) || streamNo < 1) {
    return json({ error: "Missing source, id, or streamNo" }, 400);
  }

  // Cloudflare edge IPs get stub HTML from embed.st (NOT FOUND / SANDBOX).
  // Redirect the browser iframe to the real provider embed instead.
  return new Response(null, {
    status: 302,
    headers: corsHeaders({ Location: embedStPlayerUrl(source, id, streamNo) }),
  });
}

const FPL_API_BASE = "https://fantasy.premierleague.com/api";

async function fetchFplJson(path, parentSignal, timeoutMs = 9000) {
  const deadline = coachDeadline(parentSignal, timeoutMs);
  try {
    const response = await abortable(() => fetch(`${FPL_API_BASE}/${path}`, {
      headers: { Accept: "application/json", "User-Agent": IOS_SAFARI_USER_AGENT },
      signal: deadline.signal,
      redirect: "error",
      cf: { cacheTtl: path === "bootstrap-static/" || path === "fixtures/" ? 120 : 30 },
    }), deadline.signal);
    if (!response.ok) throw new Error(`FPL ${path} returned ${response.status}`);
    const cacheAge = Number(response.headers.get("age"));
    const responseDate = Date.parse(response.headers.get("date") || "");
    if (cacheAge > 300 || (Number.isFinite(responseDate) && Date.now() - responseDate > 300_000)) {
      throw new Error("Official FPL response is stale");
    }
    return await boundedJSON(response, 4 * 1024 * 1024, deadline.signal);
  } finally {
    deadline.dispose();
  }
}

function finiteInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

function compactPlayer(player) {
  if (!player) return null;
  return {
    id: player.id,
    name: player.web_name,
    full_name: `${player.first_name || ""} ${player.second_name || ""}`.trim(),
    selectable: player.can_select !== false && player.status !== "u",
    team: player.team,
    position: player.element_type,
    cost: player.now_cost,
    status: player.status,
    news: player.news,
    chance_next: player.chance_of_playing_next_round,
    form: player.form,
    points_per_game: player.points_per_game,
    ep_next: player.ep_next,
    selected_percent: player.selected_by_percent,
    minutes: player.minutes,
    starts: player.starts,
    xg: player.expected_goals,
    xa: player.expected_assists,
    xgi: player.expected_goal_involvements,
    xgi_per_90: player.expected_goal_involvements_per_90,
    defensive_contribution: player.defensive_contribution,
    penalties_order: player.penalties_order,
    direct_freekicks_order: player.direct_freekicks_order,
    corners_order: player.corners_and_indirect_freekicks_order,
    price_projection: player.price_change_projections?.[0] || null,
  };
}

function contextPlayerIds(context) {
  const ids = new Set();
  for (const item of context?.squad || []) {
    const id = finiteInteger(item?.id);
    if (id) ids.add(id);
  }
  for (const item of context?.transferOptions || []) {
    const out = finiteInteger(item?.out?.id);
    const incoming = finiteInteger(item?.in?.id);
    if (out) ids.add(out);
    if (incoming) ids.add(incoming);
  }
  for (const item of context?.captains || []) {
    const id = finiteInteger(item?.id);
    if (id) ids.add(id);
  }
  return ids;
}

function compactEvent(event) {
  if (!event) return null;
  return {
    id: event.id,
    name: event.name,
    deadline_time: event.deadline_time,
    finished: event.finished,
    data_checked: event.data_checked,
    is_current: event.is_current,
    is_next: event.is_next,
  };
}

function compactManager(manager) {
  if (!manager) return null;
  return {
    id: manager.id,
    started_event: manager.started_event,
    current_event: manager.current_event,
    summary_overall_points: manager.summary_overall_points,
    summary_overall_rank: manager.summary_overall_rank,
    summary_event_points: manager.summary_event_points,
    last_deadline_bank: manager.last_deadline_bank,
    last_deadline_value: manager.last_deadline_value,
    last_deadline_total_transfers: manager.last_deadline_total_transfers,
  };
}

function compactEntryHistory(entry) {
  if (!entry) return null;
  return {
    event: entry.event,
    points: entry.points,
    total_points: entry.total_points,
    overall_rank: entry.overall_rank,
    rank: entry.rank,
    event_transfers: entry.event_transfers,
    event_transfers_cost: entry.event_transfers_cost,
    points_on_bench: entry.points_on_bench,
    bank: entry.bank,
    value: entry.value,
  };
}

function compactHistory(history) {
  if (!history) return null;
  return {
    current: (history.current || []).slice(-8).map(compactEntryHistory),
    chips: (history.chips || []).map((chip) => ({ name: chip.name, event: chip.event, time: chip.time })),
  };
}

function compactPicks(picks) {
  if (!picks) return null;
  return {
    active_chip: picks.active_chip,
    automatic_subs: picks.automatic_subs || [],
    entry_history: compactEntryHistory(picks.entry_history),
    picks: (picks.picks || []).map((pick) => ({
      element: pick.element,
      position: pick.position,
      multiplier: pick.multiplier,
      is_captain: pick.is_captain,
      is_vice_captain: pick.is_vice_captain,
      purchase_price: pick.purchase_price,
      selling_price: pick.selling_price,
    })),
  };
}

// Symbol-keyed validation data stays server-side: JSON sent to the model
// contains relevant evidence, not an unnecessary full player-catalog payload.
const COACH_TRANSFER_CONTEXT = Symbol("coach-transfer-validation-context");

export async function buildOfficialFplEvidence(body, signal) {
  const managerId = finiteInteger(body.managerId);
  const rivalId = finiteInteger(body.rivalId);
  const [bootstrap, fixtures, manager, history] = await Promise.all([
    fetchFplJson("bootstrap-static/", signal),
    fetchFplJson("fixtures/", signal),
    managerId ? fetchFplJson(`entry/${managerId}/`, signal) : Promise.resolve(null),
    managerId ? fetchFplJson(`entry/${managerId}/history/`, signal) : Promise.resolve(null),
  ]);
  const currentEvent = bootstrap.events?.find((event) => event.is_current) || null;
  const nextEvent = bootstrap.events?.find((event) => event.is_next) || null;
  const planningEvent = currentEvent || nextEvent;
  const currentEventId = finiteInteger(planningEvent?.id);
  const afterDeadline = planningEvent?.deadline_time
    ? Date.now() >= Date.parse(planningEvent.deadline_time)
    : false;

  const pickEvent = afterDeadline ? currentEventId : Math.max(1, (currentEventId || 1) - 1);
  const optionalEvidence = (path) => fetchFplJson(path, signal).catch(() => { signal.throwIfAborted(); return null; });
  const namedPlayers = resolveCoachPlayers({ query: body.query, history: body.history,
    players: bootstrap.elements || [], teams: bootstrap.teams || [] });
  const [picks, live, rivalPicks, playerHistory] = await Promise.all([
    managerId && currentEventId ? optionalEvidence(`entry/${managerId}/event/${pickEvent}/picks/`) : null,
    afterDeadline && currentEventId ? optionalEvidence(`event/${currentEventId}/live/`) : null,
    afterDeadline && currentEventId && rivalId ? optionalEvidence(`entry/${rivalId}/event/${currentEventId}/picks/`) : null,
    isFplScoringQuestion(body.query) || !namedPlayers.complete ? []
      : collectCoachPlayerHistory(namedPlayers.playerIDs, { fetchJSON: fetchFplJson, signal }),
  ]);

  const requestedIds = contextPlayerIds(body.context);
  for (const id of namedPlayers.playerIDs) requestedIds.add(id);
  for (const pick of picks?.picks || []) requestedIds.add(pick.element);
  for (const pick of rivalPicks?.picks || []) requestedIds.add(pick.element);
  const available = (bootstrap.elements || [])
    .filter((player) => player.status !== "u" && player.can_select !== false)
    .sort((a, b) => Number(b.ep_next || 0) - Number(a.ep_next || 0))
    .slice(0, 18);
  for (const player of available) requestedIds.add(player.id);
  const relevantPlayers = (bootstrap.elements || [])
    .filter((player) => requestedIds.has(player.id))
    .map(compactPlayer);
  const relevantTeams = new Set(relevantPlayers.map((player) => player.team));
  const horizonEnd = (currentEventId || 1)
    + Math.min(8, Math.max(1, Number(body.context?.profile?.planningHorizon || 5)));
  const relevantFixtures = (fixtures || [])
    .filter((fixture) => fixture.event >= (currentEventId || 1) && fixture.event < horizonEnd)
    .filter((fixture) => relevantTeams.has(fixture.team_h) || relevantTeams.has(fixture.team_a))
    .map((fixture) => ({
      id: fixture.id,
      event: fixture.event,
      kickoff: fixture.kickoff_time,
      finished: fixture.finished,
      home: fixture.team_h,
      away: fixture.team_a,
      home_difficulty: fixture.team_h_difficulty,
      away_difficulty: fixture.team_a_difficulty,
    }));
  const liveById = new Map((live?.elements || []).map((element) => [element.id, element.stats]));
  const maxExtraFreeTransfers = Number(bootstrap.game_settings?.max_extra_free_transfers || 0);
  const scoring = resolveFplScoring({
    event: currentEvent,
    picks,
    live,
    fixtures,
    players: bootstrap.elements,
  });

  const evidence = {
    verified_at: new Date().toISOString(),
    named_player_resolution: namedPlayers,
    requested_player_history: playerHistory,
    context_conflicts: coachContextConflicts(bootstrap.elements || [], body.context),
    evidence_limits: [
      "Official data was fetched for this answer; forecasts, model confidence, proposed transfers and every generated claim are not independently verified.",
      "Exact bank, free transfers and selling prices require private account state. Validate the complete proposed route in Transfer Lab before treating it as legal.",
      ...(playerHistory.some((item) => item.status !== "fetched") ? ["Some requested player histories were unavailable or beyond the four-player/four-second budget; do not infer minutes or injury certainty from missing history."] : []),
    ],
    current_event: compactEvent(currentEvent),
    next_event: compactEvent(nextEvent),
    verified_rules: {
      squad_size: Number(bootstrap.game_settings?.squad_squadsize || 15),
      starting_lineup_size: Number(bootstrap.game_settings?.squad_squadplay || 11),
      maximum_players_per_club: Number(bootstrap.game_settings?.squad_team_limit || 3),
      starting_budget: Number(bootstrap.game_settings?.squad_total_spend || 1000)
        / Number(bootstrap.game_settings?.ui_currency_multiplier || 10),
      max_extra_free_transfers: maxExtraFreeTransfers,
      max_free_transfers_total: maxExtraFreeTransfers + 1,
      sell_on_profit_share: Number(bootstrap.game_settings?.transfers_sell_on_fee || 0),
      sell_on_explanation: "The manager receives half of a player's price profit, rounded down to the nearest 0.1m; this is not a fixed 0.5m fee.",
      price_projection_explanation: "A price projection is only a directional likelihood signal. It is not a price change, cash gain, selling profit, or guarantee.",
      exact_free_transfers_and_selling_prices_require_authenticated_account_state: true,
    },
    chip_definitions: bootstrap.chips,
    manager: compactManager(manager),
    history: compactHistory(history),
    published_picks: compactPicks(picks),
    rival_published_picks: compactPicks(rivalPicks),
    relevant_players: relevantPlayers,
    relevant_fixtures: relevantFixtures,
    relevant_live_stats: Array.from(requestedIds)
      .map((id) => ({ id, stats: liveById.get(id) }))
      .filter((item) => item.stats),
    scoring,
  };
  evidence[COACH_TRANSFER_CONTEXT] = coachTransferContext({ bootstrap, picks, manager, context: body.context });
  return evidence;
}

function coachSystemPrompt() {
  return `You are Fotty's senior Fantasy Premier League decision coach.
Use OFFICIAL_EVIDENCE as the factual authority and CLIENT_ANALYSIS only for clearly labeled Fotty projections, local drafts, preferences, validation results, and conversation memory.
NAMED_PLAYER_RESOLUTION identifies the question's players against current official bootstrap. Use resolved IDs for the question's named subjects; alternatives may use only IDs present in RELEVANT_PLAYERS. Never silently replace a missing or ambiguous subject with a popular shortlist player. Previous user questions can identify follow-up subjects, but assistant conversation text is not factual evidence. Respect CONTEXT_CONFLICTS: old client names, prices and projections never override current official identity/facts. A player present but not selectable is not a legal transfer target.
REQUESTED_PLAYER_HISTORY is bounded and may be unavailable. State that absence, distinguish past minutes from expected minutes, and never treat news/availability flags as guaranteed future selection. Cite player ID/name, relevant gameweek/fixture and the evidence fetch time in factual evidence items. Rules, fixture facts and deterministic scores are not model forecasts. Confidence is your judgment, not measured accuracy; evidence receipt and limited rule checks do not verify every generated claim or complete transfer-route legality.
Check the whole decision: deadline phase, squad legality, budget uncertainty, free transfers, hit cost, fixture horizon, blanks/doubles, availability, expected minutes, captaincy, chips, bench coverage, price projections, and the selected rival when relevant.
Never invent a statistic, press quote, injury certainty, effective ownership, price guarantee, rank prediction, or applied transfer. Never claim Fotty changes the official team. If public data cannot prove an exact selling price or free-transfer count, say so.
Interpret VERIFIED_RULES literally: max_extra_free_transfers is additional to the current free transfer, so four extra means five total. transfers_sell_on_fee is the share of price profit returned to the manager, never a fixed monetary fee.
Price projections are directional likelihood signals only; never treat a projection percentage as a price rise, realized profit, or selling-price change. Event fields are global gameweek facts, never evidence of the manager's transfers. Zero minutes is not evidence a player was omitted unless that player's fixture has started or finished.
SCORING is calculated by Fotty's deterministic rules engine. Never recalculate or contradict official_current_points, projected_points_after_safe_autosubs, transfer_cost, or the listed official/projected substitutions. The official current total may temporarily exclude safe pending automatic substitutions; in that case state both totals and label the projected total provisional.
Challenge the user's premise when evidence does not support it. Prefer a reasoned hold over activity for its own sake.
Return one JSON object with these required keys and the optional proposedTransfers key:
{"answer":"Markdown answer with a clear recommendation and downside","confidence":"low|medium|high","evidence":["specific facts used"],"assumptions":["uncertainties"],"actions":["concrete next checks or local draft steps"],"proposedTransfers":[{"out":123,"in":456}]}
When recommending a concrete transfer route, proposedTransfers must contain its simultaneous outgoing/incoming official integer player IDs (at most 15 pairs), not names. Replace each player with the same official position; use the selected baseline (CLIENT_ANALYSIS.isLocalDraft indicates a local plan, otherwise PUBLISHED_PICKS). Omit this key or use [] for a hold or advice without one concrete route. Do not combine alternative routes in one list. Fotty will validate the whole resulting squad and available budget estimate. Never claim private budget, selling prices, transfer allowance, hit cost or route legality has been verified by the model. Prose alone is never a validated transfer plan.`;
}

function coachUsage(completion) {
  if (!completion?.usage) return undefined;
  return {
    promptTokens: Number(completion.usage.prompt_tokens || 0),
    completionTokens: Number(completion.usage.completion_tokens || 0),
    totalTokens: Number(completion.usage.total_tokens || 0),
    cacheHitTokens: Number(completion.usage.prompt_cache_hit_tokens || 0),
    cacheMissTokens: Number(completion.usage.prompt_cache_miss_tokens || 0),
    reasoningTokens: Number(completion.usage.completion_tokens_details?.reasoning_tokens || 0),
  };
}

export function coachRuleContradictions(result) {
  const text = JSON.stringify(result || {});
  const contradictions = [];
  if (/max(?:imum)?(?:\s+of)?\s+4\s+(?:saved\s+)?(?:free\s+)?transfers?/i.test(text)) {
    contradictions.push("The answer confused four extra transfers with the five-transfer total cap.");
  }
  if (/(?:0\.5m[^.]{0,30}(?:fee|charge)|(?:fee|charge)[^.]{0,30}0\.5m)/i.test(text)) {
    contradictions.push("The answer described the sell-on profit share as a fixed 0.5m fee.");
  }
  if (/(?:price\s+)?project(?:ion|ed)[^.]{0,80}(?:realized\s+profit|lock\s+in[^.]{0,20}(?:gain|profit)|selling\s+price\s+(?:gain|change))/i.test(text)) {
    contradictions.push("The answer treated a directional price projection as a realized price or profit change.");
  }
  return contradictions;
}

export function coachResultIsComplete(result) {
  if (!result || typeof result !== "object") return false;
  const answer = typeof result.answer === "string" ? result.answer.trim() : "";
  const confidence = typeof result.confidence === "string" ? result.confidence.toLowerCase() : "";
  return answer.length > 0
    && answer.length <= 8_000
    && ["low", "medium", "high"].includes(confidence)
    && Array.isArray(result.evidence)
    && result.evidence.some((item) => String(item).trim().length > 0)
    && Array.isArray(result.assumptions)
    && result.assumptions.some((item) => String(item).trim().length > 0)
    && Array.isArray(result.actions)
    && result.actions.some((item) => String(item).trim().length > 0);
}

async function handleFplCoach(request, env) {
  const deadline = coachDeadline(request.signal);
  try {
    return await abortable(() => handleFplCoachWithinDeadline(request, env, deadline.signal), deadline.signal);
  } catch {
    return json({ error: deadline.signal.aborted ? "The Coach request ended before completion. No automatic retry was made." : "The Coach request failed." }, 504);
  } finally {
    deadline.dispose();
  }
}

async function handleFplCoachWithinDeadline(request, env, signal) {
  const installId = request.headers.get("x-fotty-install-id")?.trim() || "";
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(installId)) {
    return json({ error: "Missing or invalid installation identifier." }, 400);
  }
  const parsed = await readCoachRequest(request, signal);
  signal.throwIfAborted();
  if (parsed.error) return json({ error: parsed.error }, parsed.status);
  const { body } = parsed;
  const { query } = body;
  const clientAddress = request.headers.get("cf-connecting-ip") || "unknown";
  const limited = await abortable(() => checkCoachLimit(env.FPL_COACH_RATE_LIMITER, `fpl-coach:${clientAddress}:${installId}`), signal);
  if (limited) return json({ error: limited.error }, limited.status, { "Retry-After": "60" });
  const scoringQuestion = isFplScoringQuestion(query);
  if (scoringQuestion) {
    // Deterministic scoring is free, but it still performs multiple official
    // FPL requests. Installation IDs are client-generated, so bind this path
    // to the connection and a global capacity key as well as the installation.
    const scoringClientLimit = await abortable(
      () => checkCoachLimit(env.FPL_COACH_RATE_LIMITER, `fpl-scoring:${clientAddress}`),
      signal
    );
    if (scoringClientLimit) return json({ error: scoringClientLimit.error }, scoringClientLimit.status, { "Retry-After": "60" });
    const scoringCapacity = await abortable(
      () => checkCoachLimit(env.FPL_COACH_CAPACITY_RATE_LIMITER, "fpl-scoring-capacity"),
      signal
    );
    if (scoringCapacity) return json({ error: scoringCapacity.error }, scoringCapacity.status, { "Retry-After": "60" });
  } else {
    const accessError = await authorizePaidCoach(request, env);
    if (accessError) return json({ error: accessError.error }, accessError.status);
  }

  let officialEvidence;
  let officialStatus = "fresh";
  try {
    officialEvidence = await buildOfficialFplEvidence(body, signal);
  } catch {
    signal.throwIfAborted();
    officialStatus = "client-context-only";
    officialEvidence = { error: "Official FPL refresh failed; use client timestamps and state uncertainty." };
  }

  // Factual scoring stays deterministic even when the official refresh fails.
  if (scoringQuestion) {
    return json(deterministicFplScoringResponse(
      officialEvidence.scoring,
      officialEvidence.verified_at || new Date().toISOString()
    ));
  }

  const clarification = coachPlayerClarification(officialEvidence.named_player_resolution);
  if (clarification) return json({ error: clarification }, 422);
  if (officialStatus === "client-context-only") {
    const unresolved = resolveCoachPlayers({ query, history: body.history });
    if (unresolved.mentions.length) return json({ error: "Official player evidence could not be refreshed. I cannot verify the named player from old client context; try again later with the full name and club." }, 503);
  }
  if (officialEvidence.requested_player_history?.some((item) => item.status !== "fetched")) officialStatus = "fresh-partial";

  if (!env.DEEPSEEK_API_KEY) return json({ error: "Smart coach is not configured." }, 503);
  const capacity = await abortable(() => checkCoachLimit(env.FPL_COACH_CAPACITY_RATE_LIMITER, "fpl-coach-capacity"), signal);
  if (capacity) return json({ error: capacity.error }, capacity.status, { "Retry-After": "60" });
  const allowance = await reservePaidCoach(env, signal);
  if (allowance) return json({ error: allowance.error }, allowance.status);

  const prompt = `QUESTION:\n${query}\n\nOFFICIAL_EVIDENCE:\n${JSON.stringify(officialEvidence)}\n\nCLIENT_ANALYSIS:\n${JSON.stringify(body.context || {})}\n\nRECENT_CONVERSATION:\n${JSON.stringify((body.history || []).slice(-8))}`;
  try {
    const upstream = await abortable(() => fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
        "Content-Type": "application/json",
      },
      signal,
      redirect: "error",
      body: JSON.stringify({
        model: env.FPL_COACH_MODEL || "deepseek-v4-flash",
        messages: [
          { role: "system", content: coachSystemPrompt() },
          { role: "user", content: prompt },
        ],
        // The evidence packet and system policy provide the decision structure.
        // Non-thinking mode avoids spending the entire completion budget on hidden
        // reasoning before JSON output, which DeepSeek can otherwise truncate.
        thinking: { type: "disabled" },
        response_format: { type: "json_object" },
        max_tokens: 1400,
        stream: false,
        user_id: installId,
      }),
    }), signal);
    if (!upstream.ok) {
      return json(
        { error: "The reasoning provider is temporarily unavailable." },
        upstream.status === 429 ? 429 : 502
      );
    }
    const completion = await boundedJSON(upstream, 512 * 1024, signal);
    const content = completion?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      return json({
        error: "The coach returned an empty answer.",
        model: completion?.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
        finishReason: completion?.choices?.[0]?.finish_reason || "unknown",
        usage: coachUsage(completion),
      }, 502);
    }
    let result;
    try {
      result = JSON.parse(content);
    } catch {
      return json({
        error: "The coach returned incomplete structured output.",
        model: completion?.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
        finishReason: completion?.choices?.[0]?.finish_reason || "unknown",
        usage: coachUsage(completion),
      }, 502);
    }
    if (!coachResultIsComplete(result)) {
      return json({
        error: "The coach returned incomplete structured output.",
        model: completion?.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
        finishReason: completion?.choices?.[0]?.finish_reason || "unknown",
        usage: coachUsage(completion),
      }, 502);
    }
    const contradictions = coachRuleContradictions(result);
    if (contradictions.length) {
      return json({
        error: "The coach answer contradicted verified FPL rules.",
        contradictions,
        model: completion?.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
        finishReason: completion?.choices?.[0]?.finish_reason || "unknown",
        usage: coachUsage(completion),
      }, 502);
    }
    const transferValidation = validateCoachTransfers(result.proposedTransfers, officialEvidence[COACH_TRANSFER_CONTEXT]);
    if (transferValidation.status === "invalid") {
      return json({ error: `The suggested transfer route failed whole-squad validation: ${transferValidation.reasons.join(" ")} No moves were applied and no automatic paid retry was made.`,
        transferValidation, model: completion?.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
        usage: coachUsage(completion) }, 422);
    }
    return json({
      answer: String(result.answer || "No recommendation was returned."),
      confidence: ["low", "medium", "high"].includes(result.confidence) ? result.confidence : "low",
      evidence: Array.isArray(result.evidence) ? result.evidence.slice(0, 8).map(String) : [],
      assumptions: [...transferValidation.reasons, ...(officialEvidence.evidence_limits || ["Official refresh failed; client context is not current verified evidence."]),
        ...(officialEvidence.context_conflicts || []), ...(Array.isArray(result.assumptions) ? result.assumptions.map(String) : [])].slice(0, 8),
      actions: Array.isArray(result.actions) ? result.actions.slice(0, 8).map(String) : [],
      source: "DeepSeek",
      model: completion.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
      finishReason: completion?.choices?.[0]?.finish_reason || "unknown",
      verifiedAt: officialEvidence.verified_at || new Date().toISOString(),
      officialDataStatus: officialStatus,
      usage: coachUsage(completion),
      proposedTransfers: Array.isArray(result.proposedTransfers) ? result.proposedTransfers.map(({ out, in: incoming }) => ({ out, in: incoming })) : undefined,
      transferValidation,
    });
  } catch (error) {
    return json(
      { error: error?.name === "AbortError" ? "The coach timed out." : "The coach request failed." },
      504
    );
  }
}

const worker = {
  async scheduled(_controller, env, ctx) {
    if (env.CRICKET_FIXTURES) ctx.waitUntil(cricketRegistryStub(env).fetch(new Request("https://cricket-registry.invalid/refresh", { method: "POST" }))
      .then((response) => { if (!response.ok) throw new Error("Cricket scheduled refresh failed"); }));
    if (sportsFixturesEnabled(env)) ctx.waitUntil(mapSportsSources(async (source) => {
      if (source.supported === false) return;
      try {
        const response = await sportsRegistryStub(env, source).fetch(sportsRegistryRequest(source, true));
        if (!response.ok) throw new Error("Sports scheduled refresh failed");
      } catch { logWorkerEvent("warn", "sports_fixture_registry_unavailable", { sourceGroup: source.id }); }
    }, effectiveSportsSources(env)));
  },
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    const url = new URL(request.url);
    if (url.pathname === "/api/fpl/coach") {
      if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
      return handleFplCoach(request, env);
    }
    if (request.method !== "GET") return json({ error: "Method not allowed" }, 405);
    if (url.pathname === "/health" || url.pathname === "/") {
      return handleHealth(env);
    }
    if (url.pathname === "/api/football/matches" || url.pathname === "/api/football/matches/") {
      return handleFootballDataMatches(url, env);
    }
    if (url.pathname === "/api/football/live" || url.pathname === "/api/football/live/") {
      return handleAPIFootballLive(env);
    }
    if (url.pathname === "/api/cricket/cpl-fixtures" || url.pathname === "/api/cricket/cpl-fixtures/") {
      return handleCPLFixtures(env);
    }
    if (url.pathname === "/api/cricket/fixtures" || url.pathname === "/api/cricket/fixtures/") return handleCricketFixtures(env);
    if (url.pathname === "/api/sports/fixtures" || url.pathname === "/api/sports/fixtures/") return handleSportsFixtures(env);
    if (url.pathname === "/api/live/streams") return handleStreams(url);
    if (url.pathname === "/api/embed/player") return handlePlayer(url);
    return json({ error: "Not found" }, 404);
  },
};

export default worker;
