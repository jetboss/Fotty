"use client";

import { ACCOUNTS_UNAVAILABLE_MESSAGE, isAccountsEnabled } from "@/lib/accounts";
import {
  pocketBaseRequestPasswordReset,
  pocketBaseSignInWithPassword,
  pocketBaseSignUpWithPassword,
} from "@/lib/pocketbase-client-auth";
import { isStaticFottyHost } from "@/lib/fotty-api-fetch";
import { allowLocalAuth } from "@/lib/runtime-env";

const AUTH_KEY = "fotty.web.auth.v1";
const AUTH_EVENT = "fotty:auth";

export interface FottyAuthSession {
  email: string;
  signedInAt: string;
  token?: string;
  userID?: string;
  provider?: "pocketbase" | "local" | "qr";
  entitlement?: "free" | "plus" | "supporter" | "collab" | "builder";
  /** ISO date — empty / omitted means lifetime access for paid plans. */
  entitlementExpiresAt?: string | null;
}

let cachedRaw: string | null | undefined;
let cachedSession: FottyAuthSession | null = null;

function readRaw(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(AUTH_KEY);
  } catch {
    return null;
  }
}

export function getAuthSession(): FottyAuthSession | null {
  const raw = readRaw();
  if (raw === cachedRaw) return cachedSession;

  cachedRaw = raw;
  if (!raw) {
    cachedSession = null;
    return null;
  }
  try {
    const parsed = JSON.parse(raw) as FottyAuthSession;
    cachedSession = parsed?.email && typeof parsed.email === "string" ? parsed : null;
    return cachedSession;
  } catch {
    cachedSession = null;
    return null;
  }
}

export function setAuthSession(session: FottyAuthSession) {
  if (typeof window === "undefined") return;
  const raw = JSON.stringify(session);
  cachedRaw = raw;
  cachedSession = session;
  window.localStorage.setItem(AUTH_KEY, raw);
  window.dispatchEvent(new CustomEvent(AUTH_EVENT));
}

export function clearAuthSession() {
  if (typeof window === "undefined") return;
  cachedRaw = null;
  cachedSession = null;
  window.localStorage.removeItem(AUTH_KEY);
  window.dispatchEvent(new CustomEvent(AUTH_EVENT));
}

function normalizePassword(password: string): string {
  return password.trim();
}

async function shouldUseDirectPocketBaseAuth(response: Response | null) {
  if (typeof window !== "undefined" && isStaticFottyHost()) return true;
  if (!response) return true;
  if (response.status === 404) return true;
  const contentType = response.headers.get("content-type") || "";
  return !contentType.includes("application/json");
}

async function fetchLocalSessionAccess(email: string): Promise<Pick<FottyAuthSession, "entitlement" | "entitlementExpiresAt">> {
  try {
    const response = await fetch("/api/pocketbase/entitlement", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email }),
    });
    if (!response.ok) return { entitlement: "free", entitlementExpiresAt: null };
    const payload = (await response.json()) as Pick<FottyAuthSession, "entitlement" | "entitlementExpiresAt">;
    return {
      entitlement: payload.entitlement || "free",
      entitlementExpiresAt: payload.entitlementExpiresAt ?? null,
    };
  } catch {
    return { entitlement: "free", entitlementExpiresAt: null };
  }
}

export async function signUpWithPassword(
  email: string,
  password: string,
  displayName?: string
): Promise<void> {
  if (!isAccountsEnabled()) {
    throw new Error(ACCOUNTS_UNAVAILABLE_MESSAGE);
  }
  const trimmed = email.trim().toLowerCase();
  const normalizedPassword = normalizePassword(password);
  if (!trimmed) {
    throw new Error("Enter your email.");
  }
  if (normalizedPassword.length < 8) {
    throw new Error("Password must be at least 8 characters.");
  }

  let response: Response | null = null;
  try {
    response = await fetch("/api/pocketbase/register", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email: trimmed, password: normalizedPassword, displayName: displayName?.trim() || "" }),
    });
  } catch {
    response = null;
  }

  if (await shouldUseDirectPocketBaseAuth(response)) {
    const session = await pocketBaseSignUpWithPassword(trimmed, normalizedPassword, displayName);
    setAuthSession(session);
    return;
  }

  if (!response?.ok) {
    const payload = (await response?.json().catch(() => ({}))) as { error?: string };
    throw new Error(typeof payload.error === "string" ? payload.error : "Sign-up failed.");
  }

  const session = (await response.json()) as FottyAuthSession;
  setAuthSession(session);
}

export async function signInWithPassword(email: string, password: string): Promise<void> {
  if (!isAccountsEnabled()) {
    throw new Error(ACCOUNTS_UNAVAILABLE_MESSAGE);
  }
  const trimmed = email.trim().toLowerCase();
  const normalizedPassword = normalizePassword(password);
  if (!trimmed) {
    throw new Error("Enter your email.");
  }
  if (!normalizedPassword) {
    throw new Error("Enter your password.");
  }

  let response: Response | null = null;
  try {
    response = await fetch("/api/pocketbase/auth", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email: trimmed, password: normalizedPassword }),
    });
  } catch {
    response = null;
  }

  if (await shouldUseDirectPocketBaseAuth(response)) {
    const session = await pocketBaseSignInWithPassword(trimmed, normalizedPassword);
    setAuthSession(session);
    return;
  }

  if (response?.ok) {
    const session = (await response.json()) as FottyAuthSession;
    setAuthSession(session);
    return;
  }

  const payload = (await response?.json().catch(() => ({}))) as { error?: string };
  const serverMessage = typeof payload.error === "string" ? payload.error : "Sign-in failed.";

  if (!allowLocalAuth) {
    throw new Error(serverMessage);
  }

  await new Promise((r) => setTimeout(r, 200));
  const access = await fetchLocalSessionAccess(trimmed);
  setAuthSession({
    email: trimmed,
    signedInAt: new Date().toISOString(),
    provider: "local",
    entitlement: access.entitlement,
    entitlementExpiresAt: access.entitlementExpiresAt,
  });
}

export async function deleteAccount(password: string, confirm: string): Promise<void> {
  if (!isAccountsEnabled()) {
    throw new Error(ACCOUNTS_UNAVAILABLE_MESSAGE);
  }
  const session = getAuthSession();
  if (!session?.email) {
    throw new Error("Sign in to delete your account.");
  }
  if (session.provider === "local") {
    throw new Error("Local accounts cannot be deleted here. Sign out instead.");
  }

  const normalizedPassword = normalizePassword(password);
  if (!normalizedPassword) {
    throw new Error("Enter your password.");
  }
  if (confirm.trim() !== "DELETE") {
    throw new Error('Type DELETE in the confirmation field.');
  }

  let response: Response;
  try {
    response = await fetch("/api/pocketbase/delete-account", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        email: session.email.trim().toLowerCase(),
        password: normalizedPassword,
        confirm: "DELETE",
      }),
    });
  } catch {
    throw new Error("Account deletion is temporarily unavailable.");
  }

  if (!response.ok) {
    const payload = (await response.json().catch(() => ({}))) as { error?: string };
    throw new Error(typeof payload.error === "string" ? payload.error : "Could not delete account.");
  }

  clearAuthSession();
}
