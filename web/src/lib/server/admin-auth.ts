import type { NextRequest } from "next/server";

const COOKIE_NAME = "fotty_admin";
const SESSION_MS = 7 * 24 * 60 * 60 * 1000;

export function getAdminPassword() {
  return process.env.FOTTY_ADMIN_PASSWORD?.trim() || "";
}

export function isAdminConfigured() {
  return Boolean(getAdminPassword());
}

function bytesToHex(bytes: ArrayBuffer) {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqualHex(left: string, right: string) {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let index = 0; index < left.length; index += 1) {
    diff |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return diff === 0;
}

async function hmacHex(exp: number) {
  const secret = getAdminPassword();
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(String(exp)));
  return bytesToHex(signature);
}

export async function createAdminSessionToken() {
  const exp = Date.now() + SESSION_MS;
  return `${exp}.${await hmacHex(exp)}`;
}

export async function verifyAdminSessionToken(token: string | undefined | null) {
  if (!token || !isAdminConfigured()) return false;
  const [expRaw, sig] = token.split(".");
  if (!expRaw || !sig) return false;

  const exp = Number(expRaw);
  if (!Number.isFinite(exp) || Date.now() > exp) return false;

  const expected = await hmacHex(exp);
  return timingSafeEqualHex(sig, expected);
}

export function adminCookieName() {
  return COOKIE_NAME;
}

export function adminCookieOptions() {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/",
    maxAge: SESSION_MS / 1000,
  };
}

export async function isAdminRequest(request: NextRequest) {
  const token = request.cookies.get(COOKIE_NAME)?.value;
  return verifyAdminSessionToken(token);
}
