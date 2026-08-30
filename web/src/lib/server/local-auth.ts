/** Server-only local auth gate — never trust client-inlined flags alone. */

export function isLocalAuthEnabled(): boolean {
  if (process.env.NODE_ENV === "production") {
    return false;
  }
  return process.env.NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH === "true";
}
