import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import type { FottyPlan } from "@/lib/entitlements";
import { isPaidPlan } from "@/lib/billing";
import { v2HomePath } from "@/lib/v2/preview";
import { getAdminPassword } from "@/lib/server/admin-auth";
import { getWatchStreamSecret } from "@/lib/server/watch-stream-secret";

const DATA_DIR = path.join(process.cwd(), ".data");
const LINKS_PATH = path.join(DATA_DIR, "qr-login-links.json");
const LINK_TTL_MS = 15 * 60 * 1000;
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export interface QrLoginLinkRecord {
  id: string;
  tokenHash: string;
  userID: string;
  email: string;
  entitlement: FottyPlan;
  entitlementExpiresAt?: string | null;
  returnTo: string;
  createdAt: string;
  expiresAt: string;
  usedAt?: string;
}

interface QrLoginLinksFile {
  links: Record<string, QrLoginLinkRecord>;
}

export interface QrSessionPayload {
  kind: "qr-session";
  email: string;
  userID: string;
  entitlement: FottyPlan;
  entitlementExpiresAt?: string | null;
  exp: number;
}

function qrSecret() {
  return getWatchStreamSecret() || getAdminPassword();
}

function tokenHash(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

function normalizeReturnTo(value?: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return v2HomePath();
  return value;
}

function normalizeEntitlement(value: unknown): FottyPlan {
  if (value === "plus" || value === "supporter" || value === "collab" || value === "builder") return value;
  return "free";
}

async function readLinksFile(): Promise<QrLoginLinksFile> {
  try {
    const raw = await readFile(LINKS_PATH, "utf8");
    const parsed = JSON.parse(raw) as QrLoginLinksFile;
    return parsed?.links && typeof parsed.links === "object" ? parsed : { links: {} };
  } catch {
    return { links: {} };
  }
}

async function writeLinksFile(file: QrLoginLinksFile) {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(LINKS_PATH, `${JSON.stringify(file, null, 2)}\n`, "utf8");
}

export async function createQrLoginLink(input: {
  userID: string;
  email: string;
  entitlement?: string;
  entitlementExpiresAt?: string | null;
  returnTo?: string | null;
}) {
  const email = input.email.trim().toLowerCase();
  const userID = input.userID.trim();
  if (!email || !userID) {
    return { ok: false as const, error: "User is required." };
  }

  const now = Date.now();
  const token = randomBytes(32).toString("base64url");
  const record: QrLoginLinkRecord = {
    id: randomBytes(10).toString("base64url"),
    tokenHash: tokenHash(token),
    userID,
    email,
    entitlement: normalizeEntitlement(input.entitlement),
    entitlementExpiresAt: input.entitlementExpiresAt ?? null,
    returnTo: normalizeReturnTo(input.returnTo),
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + LINK_TTL_MS).toISOString(),
  };

  const file = await readLinksFile();
  file.links[record.id] = record;
  await writeLinksFile(file);
  return { ok: true as const, token, record };
}

function signSession(payload: QrSessionPayload) {
  const secret = qrSecret();
  if (!secret) return null;
  const body = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  const sig = createHmac("sha256", secret).update(body).digest("base64url");
  return `qr.${body}.${sig}`;
}

export async function redeemQrLoginToken(token: string) {
  const secret = qrSecret();
  if (!secret) return { ok: false as const, error: "QR login is not configured." };

  const hash = tokenHash(token.trim());
  const file = await readLinksFile();
  const record = Object.values(file.links).find((link) => link.tokenHash === hash);
  if (!record) return { ok: false as const, error: "This login link is invalid or has already been used." };
  if (record.usedAt) return { ok: false as const, error: "This login link has already been used." };
  if (Date.now() > new Date(record.expiresAt).getTime()) {
    return { ok: false as const, error: "This login link expired. Ask for a fresh QR code." };
  }

  record.usedAt = new Date().toISOString();
  file.links[record.id] = record;
  await writeLinksFile(file);

  const payload: QrSessionPayload = {
    kind: "qr-session",
    email: record.email,
    userID: record.userID,
    entitlement: record.entitlement,
    entitlementExpiresAt: record.entitlementExpiresAt ?? null,
    exp: Date.now() + SESSION_TTL_MS,
  };
  const sessionToken = signSession(payload);
  if (!sessionToken) return { ok: false as const, error: "QR login is not configured." };

  return {
    ok: true as const,
    session: {
      email: record.email,
      token: sessionToken,
      userID: record.userID,
      signedInAt: new Date().toISOString(),
      provider: "qr" as const,
      entitlement: isPaidPlan(record.entitlement) ? record.entitlement : "free",
      entitlementExpiresAt: record.entitlementExpiresAt ?? null,
    },
    returnTo: record.returnTo,
  };
}

export function verifyQrSessionToken(token: string | undefined | null): QrSessionPayload | null {
  const secret = qrSecret();
  if (!secret || !token?.startsWith("qr.")) return null;
  const [, body, sig] = token.split(".");
  if (!body || !sig) return null;
  const expected = createHmac("sha256", secret).update(body).digest("base64url");
  try {
    const left = Buffer.from(sig, "utf8");
    const right = Buffer.from(expected, "utf8");
    if (left.length !== right.length || !timingSafeEqual(left, right)) return null;
  } catch {
    return null;
  }

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as QrSessionPayload;
    if (payload.kind !== "qr-session" || !payload.email || !payload.userID || Date.now() > payload.exp) return null;
    return { ...payload, entitlement: normalizeEntitlement(payload.entitlement) };
  } catch {
    return null;
  }
}
