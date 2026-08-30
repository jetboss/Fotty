export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getPocketBaseUrl } from "@/lib/fotty-config";
import { rejectIfAccountsDisabled } from "@/lib/server/accounts-disabled";

const POCKETBASE_BASE = getPocketBaseUrl();

type SyncType = "teamFollow" | "matchReminder" | "collabInquiry" | "supportPledge";

const COLLECTIONS: Record<SyncType, string> = {
  teamFollow: "team_follows",
  matchReminder: "match_reminders",
  collabInquiry: "partner_inquiries",
  supportPledge: "support_pledges",
};

function normalizeKey(value: string) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "item";
}

async function pocketBaseRequest(path: string, token: string, init: RequestInit = {}) {
  return fetch(`${POCKETBASE_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
      ...init.headers,
    },
    cache: "no-store",
  });
}

async function findExisting(collection: string, token: string, filter: string) {
  const url = new URL(`${POCKETBASE_BASE}/api/collections/${collection}/records`);
  url.searchParams.set("perPage", "1");
  url.searchParams.set("filter", filter);

  const response = await fetch(url, {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
    cache: "no-store",
  });

  if (!response.ok) return { response, id: undefined };
  const payload = await response.json();
  return { response, id: payload?.items?.[0]?.id as string | undefined };
}

async function upsertRecord(collection: string, token: string, payload: Record<string, unknown>, filter?: string) {
  if (filter) {
    const existing = await findExisting(collection, token, filter);
    if (existing.response.status === 404) {
      return { ok: false, status: "missing_collection", statusCode: 404 };
    }
    if (existing.id) {
      const update = await pocketBaseRequest(`/api/collections/${collection}/records/${existing.id}`, token, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      return update.ok
        ? { ok: true, status: "updated", id: existing.id }
        : { ok: false, status: "failed", statusCode: update.status };
    }
  }

  const create = await pocketBaseRequest(`/api/collections/${collection}/records`, token, {
    method: "POST",
    body: JSON.stringify(payload),
  });

  if (create.status === 404) return { ok: false, status: "missing_collection", statusCode: 404 };
  if (!create.ok) return { ok: false, status: "failed", statusCode: create.status };
  const created = await create.json().catch(() => ({}));
  return { ok: true, status: "created", id: created.id };
}

function buildPayload(type: SyncType, userID: string, data: Record<string, unknown>) {
  if (type === "teamFollow") {
    const teamName = String(data.name || data.teamName || "").trim();
    const key = String(data.id || data.key || normalizeKey(teamName));
    return {
      payload: {
        user: userID,
        key,
        teamName,
        sportCategory: String(data.sport || data.sportCategory || "football").toLowerCase(),
        alertsEnabled: true,
      },
      filter: `user = "${userID}" && key = "${key}"`,
    };
  }

  if (type === "matchReminder") {
    const reminderKey = String(data.id || data.cid || data.title || "match");
    const startsAt = String(data.startsAt || "");
    return {
      payload: {
        user: userID,
        key: `${normalizeKey(reminderKey)}:${startsAt}`,
        matchID: String(data.id || ""),
        cid: String(data.cid || ""),
        title: String(data.title || ""),
        league: String(data.league || ""),
        sport: String(data.sport || ""),
        startsAt,
        href: String(data.href || ""),
      },
      filter: `user = "${userID}" && key = "${normalizeKey(reminderKey)}:${startsAt}"`,
    };
  }

  if (type === "collabInquiry") {
    return {
      payload: {
        user: userID,
        packageId: String(data.packageId || ""),
        packageTitle: String(data.packageTitle || ""),
        organization: String(data.organization || ""),
        contact: String(data.contact || ""),
        region: String(data.region || ""),
        audienceSize: String(data.audienceSize || ""),
        matchFocus: String(data.matchFocus || ""),
        useCase: String(data.useCase || ""),
        status: "new",
        createdAtLocal: String(data.createdAt || new Date().toISOString()),
      },
    };
  }

  return {
    payload: {
      user: userID,
      plan: String(data.plan || ""),
      title: String(data.title || ""),
      amount: typeof data.amount === "number" ? data.amount : undefined,
      contact: String(data.contact || ""),
      note: String(data.note || ""),
      status: "new",
      createdAtLocal: String(data.createdAt || new Date().toISOString()),
    },
  };
}

export async function POST(request: Request) {
  const disabled = rejectIfAccountsDisabled();
  if (disabled) return disabled;

  const body = await request.json().catch(() => ({}));
  const type = body.type as SyncType;
  const token = typeof body.token === "string" ? body.token : "";
  const userID = typeof body.userID === "string" ? body.userID : "";
  const data = body.data && typeof body.data === "object" ? body.data as Record<string, unknown> : {};

  if (!COLLECTIONS[type]) {
    return NextResponse.json({ ok: false, status: "unknown_type" }, { status: 400 });
  }

  if (!token || !userID) {
    return NextResponse.json({ ok: false, status: "missing_session" }, { status: 401 });
  }

  const { payload, filter } = buildPayload(type, userID, data);
  const result = await upsertRecord(COLLECTIONS[type], token, payload, filter);
  return NextResponse.json(result, { status: result.ok ? 200 : result.statusCode || 502 });
}
