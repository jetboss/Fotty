"use client";

import React, { createContext, useContext, useMemo, useSyncExternalStore } from "react";
import { getEntitlementState, subscribeToEntitlements, type EntitlementState } from "@/lib/entitlements";

const EntitlementContext = createContext<EntitlementState | null>(null);

const SERVER_ENTITLEMENT_STATE: EntitlementState = {
  plan: "free",
  label: "Free",
  accessDetail: "Free",
  expiresAt: null,
  isPaid: false,
  hasPlus: false,
  source: "local",
};

function getServerEntitlementState(): EntitlementState {
  return SERVER_ENTITLEMENT_STATE;
}

let clientEntitlementSnapshot: EntitlementState | null = null;

function sameEntitlementState(left: EntitlementState, right: EntitlementState) {
  return (
    left.plan === right.plan &&
    left.label === right.label &&
    left.accessDetail === right.accessDetail &&
    left.expiresAt === right.expiresAt &&
    left.isPaid === right.isPaid &&
    left.hasPlus === right.hasPlus &&
    left.source === right.source
  );
}

function getClientEntitlementState(): EntitlementState {
  const next = getEntitlementState();
  if (clientEntitlementSnapshot && sameEntitlementState(clientEntitlementSnapshot, next)) {
    return clientEntitlementSnapshot;
  }
  clientEntitlementSnapshot = next;
  return next;
}

export function EntitlementProvider({ children }: { children: React.ReactNode }) {
  const entitlement = useSyncExternalStore(subscribeToEntitlements, getClientEntitlementState, getServerEntitlementState);
  const value = useMemo(() => entitlement, [entitlement]);
  return <EntitlementContext.Provider value={value}>{children}</EntitlementContext.Provider>;
}

export function useEntitlement() {
  const value = useContext(EntitlementContext);
  if (!value) {
    return {
      plan: "free" as const,
      label: "Free",
      accessDetail: "Free",
      expiresAt: null,
      isPaid: false,
      hasPlus: false,
      source: "local" as const,
    };
  }
  return value;
}
