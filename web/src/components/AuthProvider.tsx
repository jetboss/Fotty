"use client";

import React, { createContext, useCallback, useContext, useEffect, useMemo, useSyncExternalStore } from "react";
import { isAccountsEnabled } from "@/lib/accounts";
import {
  clearAuthSession,
  getAuthSession,
  setAuthSession,
  signInWithPassword,
  signUpWithPassword,
  type FottyAuthSession,
} from "@/lib/auth";
import { refreshWatchSessionIfNeeded } from "@/lib/watch-session";
import { fetchFottyApi } from "@/lib/fotty-api-fetch";
import { pocketBaseSyncSessionEntitlement } from "@/lib/pocketbase-client-auth";
import type { FottyPlan } from "@/lib/entitlements";

interface AuthContextValue {
  session: FottyAuthSession | null;
  isReady: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, displayName?: string) => Promise<void>;
  signOut: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function subscribeToAuth(onStoreChange: () => void) {
  window.addEventListener("fotty:auth", onStoreChange);
  window.addEventListener("storage", onStoreChange);
  return () => {
    window.removeEventListener("fotty:auth", onStoreChange);
    window.removeEventListener("storage", onStoreChange);
  };
}

function getServerAuthSession() {
  return null;
}

function subscribeToClientHydration() {
  return () => {};
}

function getClientHydrated() {
  return true;
}

function getServerHydrated() {
  return false;
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const hydrated = useSyncExternalStore(subscribeToClientHydration, getClientHydrated, getServerHydrated);
  const session = useSyncExternalStore(subscribeToAuth, getAuthSession, getServerAuthSession);
  const clientSession = hydrated ? session : null;

  useEffect(() => {
    if (!isAccountsEnabled()) return;
    if (!hydrated || !session?.email || (!session.token && session.provider !== "local")) return;

    let cancelled = false;

  async function applyEntitlement(payload: {
    entitlement?: FottyPlan;
    entitlementExpiresAt?: string | null;
    token?: string;
  }) {
    const entitlement = payload.entitlement;
    const current = getAuthSession();
    if (!entitlement || !current) return;
    const expiresAt = payload.entitlementExpiresAt ?? null;
    const nextToken = payload.token || current.token;
    if (
      current.entitlement &&
      current.entitlement !== "free" &&
      entitlement === "free"
    ) {
      if (nextToken !== current.token) {
        setAuthSession({ ...current, token: nextToken });
      }
      return;
    }
    if (
      entitlement === current.entitlement &&
      (current.entitlementExpiresAt ?? null) === expiresAt &&
      nextToken === current.token
    ) {
      return;
    }
    setAuthSession({
      ...current,
      token: nextToken,
      entitlement,
      entitlementExpiresAt: expiresAt,
    });
  }

    async function syncEntitlementFromHomelab(retried = false) {
      const current = getAuthSession();
      if (!current?.token) return;

      const response = await fetchFottyApi("/api/pocketbase/entitlement", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({
          token: current.token,
          userID: current.userID,
          email: current.email,
        }),
      });

      if (cancelled) return;
      if (response.status === 401) {
        if (!retried) {
          const refreshed = await pocketBaseSyncSessionEntitlement(current);
          if (!cancelled && refreshed) {
            await applyEntitlement(refreshed);
            return syncEntitlementFromHomelab(true);
          }
          if (!cancelled && (await refreshWatchSessionIfNeeded())) {
            return syncEntitlementFromHomelab(true);
          }
        }
        return;
      }
      if (!response.ok) return;
      const payload = (await response.json()) as {
        entitlement?: FottyPlan;
        entitlementExpiresAt?: string | null;
      };
      await applyEntitlement(payload);
    }

    void syncEntitlementFromHomelab().catch(() => {
      // Keep cached session entitlement if refresh fails.
    });

    return () => {
      cancelled = true;
    };
  }, [hydrated, session?.email, session?.entitlement, session?.entitlementExpiresAt, session?.provider, session?.token, session?.userID]);

  const signIn = useCallback(async (email: string, password: string) => {
    await signInWithPassword(email, password);
  }, []);

  const signUp = useCallback(async (email: string, password: string, displayName?: string) => {
    await signUpWithPassword(email, password, displayName);
  }, []);

  const signOut = useCallback(() => {
    clearAuthSession();
  }, []);

  const value = useMemo(
    () => ({
      session: clientSession,
      isReady: hydrated,
      signIn,
      signUp,
      signOut,
    }),
    [clientSession, hydrated, signIn, signUp, signOut]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    return {
      session: null,
      isReady: false,
      signIn: async () => {},
      signUp: async () => {},
      signOut: () => {},
    };
  }
  return ctx;
}
