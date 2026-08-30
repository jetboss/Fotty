import { isAccountsEnabled } from "@/lib/accounts";
import type { FottyAuthSession } from "@/lib/auth";
import type { EntitlementState } from "@/lib/entitlements";
import { allowLocalAuth } from "@/lib/runtime-env";

export type WatchAccessReason = "sign_in" | "upgrade" | "refresh";

export function getWatchAccess(
  session: FottyAuthSession | null | undefined,
  entitlement: EntitlementState
): { allowed: boolean; reason: WatchAccessReason | null } {
  // No auth backend: open companion Watch (provider embed). Re-gate when accounts return.
  if (!isAccountsEnabled()) {
    return { allowed: true, reason: null };
  }
  if (!session?.email) {
    return { allowed: false, reason: "sign_in" };
  }
  if (!entitlement.isPaid) {
    return { allowed: false, reason: "upgrade" };
  }
  if (!session.token && !(allowLocalAuth && session.provider === "local")) {
    return { allowed: false, reason: "refresh" };
  }
  return { allowed: true, reason: null };
}
