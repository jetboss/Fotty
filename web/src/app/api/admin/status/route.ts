export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { isAdminConfigured, isAdminRequest } from "@/lib/server/admin-auth";
import { isLocalGrantsEnabled } from "@/lib/server/admin-grants-local";
import { getPocketBaseAdminTokenForRequest, getUsersCollectionFieldNames, listPocketBaseUsers } from "@/lib/server/pocketbase-admin";
import { getPocketBaseUrl } from "@/lib/fotty-config";

export async function GET(request: NextRequest) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const adminPasswordConfigured = isAdminConfigured();
  const adminToken = await getPocketBaseAdminTokenForRequest();
  const pocketbaseTokenConfigured = Boolean(adminToken);
  const pocketbaseUrl = getPocketBaseUrl();

  let pocketbaseReachable = false;
  let optionalFieldsReady: boolean | null = null;
  const requiredFields = ["entitlement", "entitlementExpiresAt", "adminNote"];
  let missingFields: string[] = [];

  if (pocketbaseTokenConfigured) {
    try {
      await listPocketBaseUsers(adminToken, { perPage: 1, page: 1 });
      pocketbaseReachable = true;
      const fieldNames = await getUsersCollectionFieldNames(adminToken);
      if (fieldNames) {
        missingFields = requiredFields.filter((name) => !fieldNames.has(name));
        optionalFieldsReady = missingFields.length === 0;
      }
    } catch {
      pocketbaseReachable = false;
    }
  }

  const usingLocalGrants = isLocalGrantsEnabled();

  return NextResponse.json({
    adminPasswordConfigured,
    pocketbaseTokenConfigured,
    pocketbaseReachable,
    pocketbaseUrl,
    optionalFieldsReady,
    missingFields,
    usingLocalGrants,
    ready: adminPasswordConfigured && (usingLocalGrants || (pocketbaseTokenConfigured && pocketbaseReachable)),
  });
}
