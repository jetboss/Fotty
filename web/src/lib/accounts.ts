/**
 * Homelab PocketBase is retired. Keep accounts off until a new auth provider ships.
 * Set NEXT_PUBLIC_ACCOUNTS_ENABLED=true only when a real backend exists.
 */

export function isAccountsEnabled(): boolean {
  return process.env.NEXT_PUBLIC_ACCOUNTS_ENABLED === "true";
}

export const ACCOUNTS_UNAVAILABLE_MESSAGE =
  "Accounts are paused while Fotty moves off the old backend. Watching is open on the web for now.";
