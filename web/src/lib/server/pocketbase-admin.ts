import { randomBytes } from "node:crypto";
import { getPocketBaseUrl } from "@/lib/fotty-config";
import type { FottyPlan } from "@/lib/entitlements";
import { isPaidPlan } from "@/lib/billing";
import { findUserIDByEmail } from "@/lib/server/pocketbase-user";
import { pocketBaseUserMessage } from "@/lib/server/pocketbase-errors";

const POCKETBASE_BASE = getPocketBaseUrl();

export interface PocketBaseUserRecord {
  id: string;
  email: string;
  username?: string;
  name?: string;
  created: string;
  updated: string;
  entitlement?: string;
  plan?: string;
  entitlementExpiresAt?: string;
  adminNote?: string;
  role?: string;
}

function authHeader(adminToken: string) {
  return adminToken.startsWith("Bearer ") ? adminToken : `Bearer ${adminToken}`;
}

function normalizeEntitlement(record: PocketBaseUserRecord): FottyPlan {
  const value = record.entitlement || record.plan;
  if (value === "free") return "free";
  if (isPaidPlan(value)) return value;
  return "free";
}

function usernameFromEmail(email: string) {
  const localPart = email.split("@")[0] || "fotty";
  const base = localPart
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "")
    .slice(0, 18);
  const suffix = randomBytes(3).toString("hex");
  return `${base || "fotty"}${suffix}`;
}

export function getPocketBaseAdminToken() {
  return process.env.POCKETBASE_ADMIN_TOKEN?.trim() || "";
}

let cachedAdminToken: { token: string; expiresAtMs: number } | null = null;

function tokenExpiresAtMs(token: string) {
  const raw = token.startsWith("Bearer ") ? token.slice("Bearer ".length).trim() : token.trim();
  const payload = raw.split(".")[1];
  if (!payload) return 0;
  try {
    const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as { exp?: number };
    return typeof decoded.exp === "number" ? decoded.exp * 1000 : 0;
  } catch {
    return 0;
  }
}

async function authenticatePocketBaseAdmin() {
  const identity = process.env.PB_ADMIN_EMAIL?.trim();
  const password = process.env.PB_ADMIN_PASSWORD?.trim();
  if (!identity || !password) return "";

  const response = await fetch(`${POCKETBASE_BASE}/api/admins/auth-with-password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ identity, password }),
    cache: "no-store",
  });

  if (!response.ok) return "";
  const payload = (await response.json()) as { token?: string };
  return payload.token?.trim() || "";
}

export async function getPocketBaseAdminTokenForRequest() {
  const now = Date.now();
  if (cachedAdminToken && cachedAdminToken.expiresAtMs - now > 60_000) {
    return cachedAdminToken.token;
  }

  const configured = getPocketBaseAdminToken();
  const configuredExpiry = configured ? tokenExpiresAtMs(configured) : 0;
  if (configured && (!configuredExpiry || configuredExpiry - now > 60_000)) {
    cachedAdminToken = { token: configured, expiresAtMs: configuredExpiry || now + 10 * 60_000 };
    return configured;
  }

  const refreshed = await authenticatePocketBaseAdmin();
  if (refreshed) {
    cachedAdminToken = {
      token: refreshed,
      expiresAtMs: tokenExpiresAtMs(refreshed) || now + 10 * 60_000,
    };
    return refreshed;
  }

  return configured;
}

export async function getUsersCollectionFieldNames(adminToken: string) {
  const response = await fetch(
    `${POCKETBASE_BASE}/api/collections?filter=${encodeURIComponent('name="users"')}`,
    {
      headers: { Accept: "application/json", Authorization: authHeader(adminToken) },
      cache: "no-store",
    }
  );

  if (!response.ok) return null;

  const listPayload = (await response.json()) as { items?: Array<{ id?: string }> };
  const collectionId = listPayload.items?.[0]?.id;
  if (!collectionId) return null;

  const detailResponse = await fetch(`${POCKETBASE_BASE}/api/collections/${collectionId}`, {
    headers: { Accept: "application/json", Authorization: authHeader(adminToken) },
    cache: "no-store",
  });
  if (!detailResponse.ok) return null;

  const collection = (await detailResponse.json()) as {
    schema?: Array<{ name: string }>;
    fields?: Array<{ name: string }>;
  };
  const entries = collection.schema || collection.fields;
  if (!entries) return null;
  return new Set(entries.map((field) => field.name));
}

export async function listPocketBaseUsers(
  adminToken: string,
  options: { page?: number; perPage?: number; search?: string } = {}
) {
  const page = options.page ?? 1;
  const perPage = Math.min(options.perPage ?? 20, 50);
  const params = new URLSearchParams({
    page: String(page),
    perPage: String(perPage),
    sort: "-created",
  });

  const search = options.search?.trim().toLowerCase();
  if (search) {
    const escaped = search.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    params.set("filter", `email ~ "${escaped}"`);
  }

  const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records?${params.toString()}`, {
    headers: { Accept: "application/json", Authorization: authHeader(adminToken) },
    cache: "no-store",
  });

  if (!response.ok) {
    const error = await response.text().catch(() => "");
    throw new Error(error || `PocketBase list failed (${response.status})`);
  }

  const payload = (await response.json()) as {
    page: number;
    perPage: number;
    totalItems: number;
    totalPages: number;
    items: PocketBaseUserRecord[];
  };

  return {
    page: payload.page,
    perPage: payload.perPage,
    totalItems: payload.totalItems,
    totalPages: payload.totalPages,
    items: payload.items.map((item) => ({
      ...item,
      entitlement: normalizeEntitlement(item),
    })),
  };
}

export async function getPocketBaseUser(adminToken: string, userID: string) {
  const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records/${userID}`, {
    headers: { Accept: "application/json", Authorization: authHeader(adminToken) },
    cache: "no-store",
  });

  if (!response.ok) return null;
  const record = (await response.json()) as PocketBaseUserRecord;
  return { ...record, entitlement: normalizeEntitlement(record) };
}

export interface UpdateUserAccessInput {
  entitlement: FottyPlan;
  entitlementExpiresAt?: string | null;
  adminNote?: string | null;
}

async function patchUser(adminToken: string, userID: string, body: Record<string, string>) {
  const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records/${userID}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: authHeader(adminToken),
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  return response;
}

// Fixed alphabet used as input to randomBytes; it is not a credential.
const TEMP_PASSWORD_CHARS = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // gitleaks:allow

export function generateTemporaryPassword(length = 14) {
  const bytes = randomBytes(length);
  let password = "";
  for (let i = 0; i < length; i += 1) {
    password += TEMP_PASSWORD_CHARS[bytes[i]! % TEMP_PASSWORD_CHARS.length];
  }
  return password;
}

export interface CreatePocketBaseUserInput {
  email: string;
  password?: string;
  name?: string;
  entitlement: FottyPlan;
  entitlementExpiresAt?: string | null;
  adminNote?: string | null;
}

function toAdminUser(record: PocketBaseUserRecord) {
  return {
    id: record.id,
    email: record.email,
    name: record.name,
    created: record.created,
    entitlement: normalizeEntitlement(record),
    entitlementExpiresAt: record.entitlementExpiresAt,
    adminNote: record.adminNote,
  };
}

export async function createPocketBaseUser(adminToken: string, input: CreatePocketBaseUserInput) {
  const email = input.email.trim().toLowerCase();
  if (!email.includes("@")) {
    return { ok: false as const, error: "Valid email is required." };
  }

  const existingID = await findUserIDByEmail(email, authHeader(adminToken));
  if (existingID) {
    return {
      ok: false as const,
      error: "An account with this email already exists. Select them in the list and update their plan instead.",
      existingUserID: existingID,
    };
  }

  const password =
    typeof input.password === "string" && input.password.trim().length >= 8
      ? input.password.trim()
      : generateTemporaryPassword();
  const generatedPassword = !input.password?.trim();

  const createBody: Record<string, string> = {
    email,
    username: usernameFromEmail(email),
    password,
    passwordConfirm: password,
    role: "user",
    entitlement: input.entitlement,
    plan: input.entitlement,
  };
  if (input.name?.trim()) createBody.name = input.name.trim();
  if (input.entitlementExpiresAt) createBody.entitlementExpiresAt = input.entitlementExpiresAt;
  if (input.adminNote?.trim()) createBody.adminNote = input.adminNote.trim();

  const createResponse = await fetch(`${POCKETBASE_BASE}/api/collections/users/records`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: authHeader(adminToken),
    },
    body: JSON.stringify(createBody),
    cache: "no-store",
  });

  let userID: string | null = null;
  let warning: string | undefined;

  if (!createResponse.ok) {
    const primaryErrorPayload = await createResponse.json().catch(() => ({}));
    const primaryError = pocketBaseUserMessage(primaryErrorPayload, "Could not create account.");
    const minimalResponse = await fetch(`${POCKETBASE_BASE}/api/collections/users/records`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: authHeader(adminToken),
      },
      body: JSON.stringify({
        email,
        username: usernameFromEmail(email),
        password,
        passwordConfirm: password,
        role: "user",
        ...(input.name?.trim() ? { name: input.name.trim() } : {}),
      }),
      cache: "no-store",
    });

    if (!minimalResponse.ok) {
      const errorPayload = await minimalResponse.json().catch(() => ({}));
      return {
        ok: false as const,
        error: pocketBaseUserMessage(errorPayload, primaryError),
      };
    }

    const minimalRecord = (await minimalResponse.json()) as PocketBaseUserRecord;
    userID = minimalRecord.id;
    warning = "Account created; applying plan and optional fields separately.";
  } else {
    const record = (await createResponse.json()) as PocketBaseUserRecord;
    userID = record.id;
  }

  if (!userID) {
    return { ok: false as const, error: "Account was created but user id is missing." };
  }

  const accessResult = await updatePocketBaseUserAccess(adminToken, userID, {
    entitlement: input.entitlement,
    entitlementExpiresAt: input.entitlementExpiresAt,
    adminNote: input.adminNote,
  });

  if (!accessResult.ok) {
    return {
      ok: false as const,
      error: accessResult.error || "Account created but plan could not be saved.",
      userID,
      temporaryPassword: generatedPassword ? password : undefined,
    };
  }

  const notePrefix = `Created by admin ${new Date().toISOString().slice(0, 10)}`;
  const mergedNote = [notePrefix, input.adminNote?.trim()].filter(Boolean).join(" — ");
  if (mergedNote !== (accessResult.user?.adminNote ?? "")) {
    await patchUser(adminToken, userID, { adminNote: mergedNote });
  }

  const user = accessResult.user ? toAdminUser(accessResult.user) : null;
  if (!user) {
    return { ok: false as const, error: "Account created but could not be loaded." };
  }

  return {
    ok: true as const,
    user: { ...user, adminNote: mergedNote || user.adminNote },
    temporaryPassword: generatedPassword ? password : undefined,
    warning: [warning, accessResult.warning].filter(Boolean).join(" ") || undefined,
  };
}

export async function updatePocketBaseUserAccess(
  adminToken: string,
  userID: string,
  input: UpdateUserAccessInput
) {
  const primary = await patchUser(adminToken, userID, {
    entitlement: input.entitlement,
    plan: input.entitlement,
  });

  if (!primary.ok) {
    const error = await primary.text().catch(() => "");
    return { ok: false as const, error: error || `Update failed (${primary.status})` };
  }

  let warning: string | undefined;
  const extras: Record<string, string> = {};
  if (input.entitlementExpiresAt !== undefined) {
    extras.entitlementExpiresAt = input.entitlementExpiresAt ?? "";
  }
  if (input.adminNote !== undefined) {
    extras.adminNote = input.adminNote ?? "";
  }

  if (Object.keys(extras).length > 0) {
    const extraResponse = await patchUser(adminToken, userID, extras);
    if (!extraResponse.ok) {
      warning =
        "Plan saved. Add optional PocketBase user fields `entitlementExpiresAt` and `adminNote` (text) to store expiry and notes.";
    }
  }

  const record = (await primary.json()) as PocketBaseUserRecord;
  const user = await getPocketBaseUser(adminToken, userID);
  return {
    ok: true as const,
    user: user ?? { ...record, entitlement: normalizeEntitlement(record) },
    warning,
  };
}

export async function deletePocketBaseUser(adminToken: string, userID: string) {
  const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/records/${userID}`, {
    method: "DELETE",
    headers: { Accept: "application/json", Authorization: authHeader(adminToken) },
    cache: "no-store",
  });

  if (!response.ok) {
    const error = await response.text().catch(() => "");
    return { ok: false as const, error: error || `Delete failed (${response.status})` };
  }

  return { ok: true as const };
}
