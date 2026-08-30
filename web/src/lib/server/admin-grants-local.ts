import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import type { FottyPlan } from "@/lib/entitlements";

export interface LocalAdminGrant {
  id: string;
  email: string;
  name?: string;
  created: string;
  updated: string;
  entitlement: FottyPlan;
  entitlementExpiresAt?: string;
  adminNote?: string;
}

interface GrantsFile {
  users: Record<string, LocalAdminGrant>;
}

const DATA_DIR = path.join(process.cwd(), ".data");
const GRANTS_PATH = path.join(DATA_DIR, "admin-grants.json");

export function localGrantId(email: string) {
  return `local:${email.trim().toLowerCase()}`;
}

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

async function readGrantsFile(): Promise<GrantsFile> {
  try {
    const raw = await readFile(GRANTS_PATH, "utf8");
    const parsed = JSON.parse(raw) as GrantsFile;
    return parsed?.users && typeof parsed.users === "object" ? parsed : { users: {} };
  } catch {
    return { users: {} };
  }
}

async function writeGrantsFile(data: GrantsFile) {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(GRANTS_PATH, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

export function isLocalGrantsEnabled() {
  return !process.env.POCKETBASE_ADMIN_TOKEN?.trim();
}

export async function listLocalGrants(options: { search?: string; page?: number; perPage?: number }) {
  const file = await readGrantsFile();
  let items = Object.values(file.users).sort((a, b) => b.created.localeCompare(a.created));

  const search = options.search?.trim().toLowerCase();
  if (search) {
    items = items.filter((user) => user.email.toLowerCase().includes(search));
  }

  const perPage = Math.min(options.perPage ?? 20, 50);
  const page = Math.max(options.page ?? 1, 1);
  const totalItems = items.length;
  const totalPages = Math.max(1, Math.ceil(totalItems / perPage));
  const start = (page - 1) * perPage;

  return {
    page,
    perPage,
    totalItems,
    totalPages,
    items: items.slice(start, start + perPage),
    source: "local" as const,
  };
}

export async function getLocalGrant(idOrEmail: string) {
  const file = await readGrantsFile();
  const byId = file.users[idOrEmail];
  if (byId) return byId;
  const email = normalizeEmail(idOrEmail);
  return file.users[localGrantId(email)] ?? file.users[email] ?? null;
}

export async function getLocalGrantByEmail(email: string) {
  return getLocalGrant(localGrantId(email));
}

export async function upsertLocalGrant(input: {
  email: string;
  name?: string;
  entitlement: FottyPlan;
  entitlementExpiresAt?: string | null;
  adminNote?: string | null;
}) {
  const email = normalizeEmail(input.email);
  if (!email.includes("@")) {
    return { ok: false as const, error: "Valid email is required." };
  }

  const file = await readGrantsFile();
  const id = localGrantId(email);
  const now = new Date().toISOString();
  const existing = file.users[id];

  const record: LocalAdminGrant = {
    id,
    email,
    name: input.name?.trim() || existing?.name,
    created: existing?.created ?? now,
    updated: now,
    entitlement: input.entitlement,
    entitlementExpiresAt:
      input.entitlementExpiresAt === null || input.entitlementExpiresAt === undefined
        ? undefined
        : input.entitlementExpiresAt,
    adminNote:
      input.adminNote === null || input.adminNote === undefined ? undefined : input.adminNote.trim() || undefined,
  };

  file.users[id] = record;
  await writeGrantsFile(file);
  return { ok: true as const, user: record };
}

export async function deleteLocalGrant(id: string) {
  const file = await readGrantsFile();
  const record = file.users[id];
  if (!record) {
    return { ok: false as const, error: "User not found." };
  }
  delete file.users[id];
  await writeGrantsFile(file);
  return { ok: true as const };
}

export async function resolveLocalEntitlement(email: string): Promise<FottyPlan | undefined> {
  const grant = await getLocalGrantByEmail(email);
  if (!grant) return undefined;
  if (grant.entitlementExpiresAt) {
    const expMs = new Date(grant.entitlementExpiresAt).getTime();
    if (Number.isFinite(expMs) && Date.now() > expMs) return "free";
  }
  return grant.entitlement;
}
