import type { FottyPlan } from "@/lib/entitlements";

export interface AdminUser {
  id: string;
  email: string;
  name?: string;
  created: string;
  entitlement: FottyPlan;
  entitlementExpiresAt?: string;
  adminNote?: string;
}
