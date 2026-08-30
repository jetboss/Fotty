/** Client-safe runtime flags (inlined at build time). */

export const isProductionBuild = process.env.NODE_ENV === "production";

const localAuthBuildFlag = process.env.NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH === "true";

/** Dev-only: never enabled in production builds even if the flag was set at compile time. */
export const allowLocalAuth = !isProductionBuild && localAuthBuildFlag;

/** Dev-only: allow local entitlement activation without checkout URLs. */
export const allowLocalEntitlements = allowLocalAuth;
