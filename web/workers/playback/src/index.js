/**
 * Fotty playback edge API — iOS parity for getfotty.com static FTP.
 *
 * Routes:
 *   GET /api/live/streams?source=&id=
 *   GET /api/embed/player?source=&id=&streamNo=
 *   GET /api/cricket/cpl-fixtures
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
import cplFixtureFallback from "../../../public/data/cpl-2026-fixtures.json" with { type: "json" };
import { cplFixtureSources, resolveCPLManifest } from "./cpl-fixture-policy.mjs";

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
// Bump with every Worker source release. Health must identify deployed code;
// availability alone is not sufficient release evidence.
const WORKER_SOURCE_VERSION = "2026-09-03.cpl-fixtures-1";
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
    "Cache-Control": "no-store",
    ...extra,
  };
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders({ "Content-Type": "application/json", ...extraHeaders }),
  });
}

async function handleCPLFixtures() {
  const requestOptions = {
    headers: { "User-Agent": "Fotty fixture service/1.0" },
    cf: { cacheEverything: true, cacheTtl: 900 },
  };
  try {
    const [liveResponse, publishedResponse, correctionResponse] = await Promise.all([
      fetch(cplFixtureSources.live, { ...requestOptions, headers: { ...requestOptions.headers, Accept: "text/html" } }),
      fetch(cplFixtureSources.published, { ...requestOptions, headers: { ...requestOptions.headers, Accept: "text/html" } }),
      fetch(cplFixtureSources.correction, { ...requestOptions, headers: { ...requestOptions.headers, Accept: "application/json" } }),
    ]);
    if (!liveResponse.ok || !publishedResponse.ok || !correctionResponse.ok) {
      throw new Error("A CPL schedule source was unavailable.");
    }
    const [verifierHTML, publishedHTML, correctionJSON] = await Promise.all([
      liveResponse.text(),
      publishedResponse.text(),
      correctionResponse.json(),
    ]);
    if (verifierHTML.length > 5_000_000 || publishedHTML.length > 1_000_000) {
      throw new Error("A CPL schedule source exceeded its size limit.");
    }
    const resolved = resolveCPLManifest({
      fallback: cplFixtureFallback,
      verifierHTML,
      publishedHTML,
      correctionJSON,
    });
    return json({
      ...resolved.manifest,
      sourceStatus: resolved.authoritativeChanges.length > 0 ? "updated" : "verified",
      warnings: resolved.reviewedVerifierChanges.map((change) => change.message),
    }, 200, { "Cache-Control": "public, max-age=300" });
  } catch {
    // A partial feed, parser change or new source conflict cannot erase the
    // reviewed schedule. Clients receive the complete bundled fallback.
    return json({
      ...cplFixtureFallback,
      sourceStatus: "last-known-good",
      warnings: ["Current schedule verification was unavailable; using the last reviewed CPL schedule."],
    }, 200, { "Cache-Control": "public, max-age=60" });
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
    const response = await fetch(upstream, {
      headers: {
        Accept: "application/json",
        "X-Auth-Token": env.FOOTBALL_DATA_API_KEY,
      },
      cf: { cacheEverything: true, cacheTtl: isLiveQuery ? 120 : 900 },
    });
    if (!response.ok) {
      return json({ error: "The football score provider is temporarily unavailable." }, response.status === 429 ? 429 : 502);
    }
    return new Response(await response.arrayBuffer(), {
      status: 200,
      headers: corsHeaders({
        "Content-Type": "application/json",
        "Cache-Control": isLiveQuery ? "public, max-age=60" : "public, max-age=300",
      }),
    });
  } catch {
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
      const response = await fetch(apiFootballLiveUpstreamURL(), {
        headers: {
          Accept: "application/json",
          "x-apisports-key": this.env.API_FOOTBALL_KEY,
        },
      });

      state.providerRemaining = integerHeader(response.headers, "x-ratelimit-requests-remaining");
      state.providerLimit = integerHeader(response.headers, "x-ratelimit-requests-limit");
      state.providerObservedAt = now;

      if (!response.ok) {
        if (response.status === 429) state.providerRemaining = 0;
        await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);
        return jsonSnapshot(
          { error: "The Premier League live-score provider is temporarily unavailable." },
          response.status === 429 ? 429 : 502,
          quotaHeaders(state, "upstream-error")
        );
      }

      const upstreamBody = await response.text();
      const providerError = apiFootballPayloadError(upstreamBody);
      if (providerError) {
        console.warn("API-Football rejected the scoped live-score query", providerError);
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
    } catch {
      await this.state.storage.put(API_FOOTBALL_QUOTA_STATE_KEY, state);
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

async function fetchVariants(provider, source, id) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6500);
  try {
    const response = await fetch(
      `${provider.baseURL}${provider.pathPrefix}/${encodeURIComponent(source)}/${encodeURIComponent(id)}`,
      {
        headers: {
          Accept: "application/json",
          Referer: provider.baseURL,
          "User-Agent": IOS_SAFARI_USER_AGENT,
        },
        signal: controller.signal,
      }
    );
    if (!response.ok) return [];
    const payload = await response.json();
    const variants = Array.isArray(payload)
      ? payload
      : payload?.streams || payload?.variants || payload?.data || payload?.result || [];
    return (Array.isArray(variants) ? variants : []).map((variant) => ({
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
  } catch {
    return [];
  } finally {
    clearTimeout(timeout);
  }
}

async function handleStreams(url) {
  const source = url.searchParams.get("source")?.trim();
  const id = url.searchParams.get("id")?.trim();
  if (!source || !id) return json({ error: "Missing source or id" }, 400);

  const providerResults = await Promise.all(
    STREAM_PROVIDERS.map((provider) => fetchVariants(provider, source, id))
  );
  const variants = providerResults
    .flat()
    .filter((variant) => variant.embedUrl)
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

  return json(variants);
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
  return Response.redirect(embedStPlayerUrl(source, id, streamNo), 302);
}

const FPL_API_BASE = "https://fantasy.premierleague.com/api";

async function fetchFplJson(path, timeoutMs = 9000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${FPL_API_BASE}/${path}`, {
      headers: { Accept: "application/json", "User-Agent": IOS_SAFARI_USER_AGENT },
      signal: controller.signal,
      cf: { cacheTtl: path === "bootstrap-static/" || path === "fixtures/" ? 120 : 30 },
    });
    if (!response.ok) throw new Error(`FPL ${path} returned ${response.status}`);
    const cacheAge = Number(response.headers.get("age"));
    const responseDate = Date.parse(response.headers.get("date") || "");
    if (cacheAge > 300 || (Number.isFinite(responseDate) && Date.now() - responseDate > 300_000)) {
      throw new Error("Official FPL response is stale");
    }
    return await response.json();
  } finally {
    clearTimeout(timeout);
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

async function buildOfficialFplEvidence(body) {
  const managerId = finiteInteger(body.managerId);
  const rivalId = finiteInteger(body.rivalId);
  const [bootstrap, fixtures, manager, history] = await Promise.all([
    fetchFplJson("bootstrap-static/"),
    fetchFplJson("fixtures/"),
    managerId ? fetchFplJson(`entry/${managerId}/`) : Promise.resolve(null),
    managerId ? fetchFplJson(`entry/${managerId}/history/`) : Promise.resolve(null),
  ]);
  const currentEvent = bootstrap.events?.find((event) => event.is_current) || null;
  const nextEvent = bootstrap.events?.find((event) => event.is_next) || null;
  const planningEvent = currentEvent || nextEvent;
  const currentEventId = finiteInteger(planningEvent?.id);
  const afterDeadline = planningEvent?.deadline_time
    ? Date.now() >= Date.parse(planningEvent.deadline_time)
    : false;

  let picks = null;
  let live = null;
  let rivalPicks = null;
  if (managerId && currentEventId) {
    const pickEvent = afterDeadline ? currentEventId : Math.max(1, currentEventId - 1);
    picks = await fetchFplJson(`entry/${managerId}/event/${pickEvent}/picks/`).catch(() => null);
  }
  if (afterDeadline && currentEventId) {
    live = await fetchFplJson(`event/${currentEventId}/live/`).catch(() => null);
    if (rivalId) {
      rivalPicks = await fetchFplJson(`entry/${rivalId}/event/${currentEventId}/picks/`).catch(() => null);
    }
  }

  const requestedIds = contextPlayerIds(body.context);
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

  return {
    verified_at: new Date().toISOString(),
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
}

function coachSystemPrompt() {
  return `You are Fotty's senior Fantasy Premier League decision coach.
Use OFFICIAL_EVIDENCE as the factual authority and CLIENT_ANALYSIS only for clearly labeled Fotty projections, local drafts, preferences, validation results, and conversation memory.
Check the whole decision: deadline phase, squad legality, budget uncertainty, free transfers, hit cost, fixture horizon, blanks/doubles, availability, expected minutes, captaincy, chips, bench coverage, price projections, and the selected rival when relevant.
Never invent a statistic, press quote, injury certainty, effective ownership, price guarantee, rank prediction, or applied transfer. Never claim Fotty changes the official team. If public data cannot prove an exact selling price or free-transfer count, say so.
Interpret VERIFIED_RULES literally: max_extra_free_transfers is additional to the current free transfer, so four extra means five total. transfers_sell_on_fee is the share of price profit returned to the manager, never a fixed monetary fee.
Price projections are directional likelihood signals only; never treat a projection percentage as a price rise, realized profit, or selling-price change. Event fields are global gameweek facts, never evidence of the manager's transfers. Zero minutes is not evidence a player was omitted unless that player's fixture has started or finished.
SCORING is calculated by Fotty's deterministic rules engine. Never recalculate or contradict official_current_points, projected_points_after_safe_autosubs, transfer_cost, or the listed official/projected substitutions. The official current total may temporarily exclude safe pending automatic substitutions; in that case state both totals and label the projected total provisional.
Challenge the user's premise when evidence does not support it. Prefer a reasoned hold over activity for its own sake.
Return one JSON object with exactly these keys:
{"answer":"Markdown answer with a clear recommendation and downside","confidence":"low|medium|high","evidence":["specific facts used"],"assumptions":["uncertainties"],"actions":["concrete next checks or local draft steps"]}`;
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
  const installId = request.headers.get("x-fotty-install-id")?.trim() || "";
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(installId)) {
    return json({ error: "Missing or invalid installation identifier." }, 400);
  }
  const clientAddress = request.headers.get("cf-connecting-ip") || "unknown";
  const limited = await checkCoachLimit(env.FPL_COACH_RATE_LIMITER, `fpl-coach:${clientAddress}:${installId}`);
  if (limited) return json({ error: limited.error }, limited.status, { "Retry-After": "60" });
  const parsed = await readCoachRequest(request);
  if (parsed.error) return json({ error: parsed.error }, parsed.status);
  const { body } = parsed;
  const { query } = body;

  let officialEvidence;
  let officialStatus = "fresh";
  try {
    officialEvidence = await buildOfficialFplEvidence(body);
  } catch {
    officialStatus = "client-context-only";
    officialEvidence = { error: "Official FPL refresh failed; use client timestamps and state uncertainty." };
  }

  // Factual scoring stays deterministic even when the official refresh fails.
  if (isFplScoringQuestion(query)) {
    return json(deterministicFplScoringResponse(
      officialEvidence.scoring,
      officialEvidence.verified_at || new Date().toISOString()
    ));
  }

  if (!env.DEEPSEEK_API_KEY) return json({ error: "Smart coach is not configured." }, 503);
  const capacity = await checkCoachLimit(env.FPL_COACH_CAPACITY_RATE_LIMITER, "fpl-coach-capacity");
  if (capacity) return json({ error: capacity.error }, capacity.status, { "Retry-After": "60" });

  const prompt = `QUESTION:\n${query}\n\nOFFICIAL_EVIDENCE:\n${JSON.stringify(officialEvidence)}\n\nCLIENT_ANALYSIS:\n${JSON.stringify(body.context || {})}\n\nRECENT_CONVERSATION:\n${JSON.stringify((body.history || []).slice(-8))}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45000);
  try {
    const upstream = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
        "Content-Type": "application/json",
      },
      signal: controller.signal,
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
    });
    if (!upstream.ok) {
      return json(
        { error: "The reasoning provider is temporarily unavailable." },
        upstream.status === 429 ? 429 : 502
      );
    }
    const completion = await upstream.json();
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
    return json({
      answer: String(result.answer || "No recommendation was returned."),
      confidence: ["low", "medium", "high"].includes(result.confidence) ? result.confidence : "low",
      evidence: Array.isArray(result.evidence) ? result.evidence.slice(0, 8).map(String) : [],
      assumptions: Array.isArray(result.assumptions) ? result.assumptions.slice(0, 8).map(String) : [],
      actions: Array.isArray(result.actions) ? result.actions.slice(0, 8).map(String) : [],
      source: "DeepSeek",
      model: completion.model || env.FPL_COACH_MODEL || "deepseek-v4-flash",
      finishReason: completion?.choices?.[0]?.finish_reason || "unknown",
      verifiedAt: officialEvidence.verified_at || new Date().toISOString(),
      officialDataStatus: officialStatus,
      usage: coachUsage(completion),
    });
  } catch (error) {
    return json(
      { error: error?.name === "AbortError" ? "The coach timed out." : "The coach request failed." },
      504
    );
  } finally {
    clearTimeout(timeout);
  }
}

const worker = {
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
      return handleCPLFixtures();
    }
    if (url.pathname === "/api/live/streams") return handleStreams(url);
    if (url.pathname === "/api/embed/player") return handlePlayer(url);
    return json({ error: "Not found" }, 404);
  },
};

export default worker;
