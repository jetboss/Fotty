export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import type { FottyPlan } from "@/lib/entitlements";
import { isAdminRequest } from "@/lib/server/admin-auth";
import { isLocalGrantsEnabled, listLocalGrants, upsertLocalGrant } from "@/lib/server/admin-grants-local";
import {
  createPocketBaseUser,
  getPocketBaseAdminTokenForRequest,
  listPocketBaseUsers,
} from "@/lib/server/pocketbase-admin";

function normalizePlan(value: unknown): FottyPlan | null {
  if (
    value === "free" ||
    value === "plus" ||
    value === "supporter" ||
    value === "collab" ||
    value === "builder"
  ) {
    return value;
  }
  return null;
}

export async function GET(request: NextRequest) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = request.nextUrl;
  const search = searchParams.get("q") || undefined;
  const page = Number(searchParams.get("page") || "1");
  const pageNum = Number.isFinite(page) && page > 0 ? page : 1;

  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (!adminToken) {
    const result = await listLocalGrants({ search, page: pageNum, perPage: 20 });
    return NextResponse.json(result);
  }

  try {
    const result = await listPocketBaseUsers(adminToken, {
      search,
      page: pageNum,
      perPage: 20,
    });
    const local = await listLocalGrants({ search, page: pageNum, perPage: 20 });
    if (result.totalItems === 0 && local.totalItems > 0) {
      return NextResponse.json({
        ...local,
        source: "local",
        warning:
          "PocketBase returned no users, so showing local admin grants. Check the PocketBase admin token or collection if you expected PocketBase accounts.",
      });
    }
    return NextResponse.json({ ...result, source: "pocketbase" });
  } catch (error) {
    const local = await listLocalGrants({ search, page: pageNum, perPage: 20 });
    if (local.totalItems > 0) {
      return NextResponse.json({
        ...local,
        source: "local",
        warning:
          "PocketBase user listing is unavailable, so showing local admin grants. Check the PocketBase admin token permissions.",
      });
    }

    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Failed to load users." },
      { status: 502 }
    );
  }
}

export async function POST(request: NextRequest) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const name = typeof body.name === "string" ? body.name.trim() : undefined;
  const password = typeof body.password === "string" ? body.password : undefined;
  const entitlement = normalizePlan(body.entitlement) ?? "plus";
  const requestedSource = body.source === "local" ? "local" : body.source === "pocketbase" ? "pocketbase" : undefined;
  const entitlementExpiresAt =
    body.entitlementExpiresAt === null || typeof body.entitlementExpiresAt === "string"
      ? body.entitlementExpiresAt
      : undefined;
  const adminNote =
    body.adminNote === null || typeof body.adminNote === "string" ? body.adminNote : undefined;

  if (!email) {
    return NextResponse.json({ error: "Email is required." }, { status: 400 });
  }

  if (password !== undefined && password.length > 0 && password.length < 8) {
    return NextResponse.json({ error: "Password must be at least 8 characters." }, { status: 400 });
  }

  if (requestedSource === "local") {
    const result = await upsertLocalGrant({
      email,
      name,
      entitlement,
      entitlementExpiresAt,
      adminNote,
    });

    if (!result.ok) {
      return NextResponse.json({ error: result.error }, { status: 400 });
    }

    return NextResponse.json({ ok: true, user: result.user, source: "local" });
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (adminToken) {
    const result = await createPocketBaseUser(adminToken, {
      email,
      name,
      password: password?.trim() || undefined,
      entitlement,
      entitlementExpiresAt,
      adminNote,
    });

    if (!result.ok) {
      const status = result.existingUserID ? 409 : result.userID ? 502 : 400;
      return NextResponse.json(
        {
          error: result.error,
          existingUserID: result.existingUserID,
          temporaryPassword: result.temporaryPassword,
        },
        { status }
      );
    }

    const sharedPassword = result.temporaryPassword ?? (password?.trim() || undefined);

    return NextResponse.json({
      ok: true,
      user: result.user,
      temporaryPassword: sharedPassword,
      warning: result.warning,
      source: "pocketbase",
    });
  }

  if (!isLocalGrantsEnabled()) {
    return NextResponse.json({ error: "POCKETBASE_ADMIN_TOKEN is not set." }, { status: 503 });
  }

  const result = await upsertLocalGrant({
    email,
    name,
    entitlement,
    entitlementExpiresAt,
    adminNote,
  });

  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }

  return NextResponse.json({ ok: true, user: result.user, source: "local" });
}
