export const dynamic = "force-dynamic";

export function generateStaticParams() {
  return [{ id: "index" }];
}

import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import type { FottyPlan } from "@/lib/entitlements";
import { isAdminRequest } from "@/lib/server/admin-auth";
import { deleteLocalGrant, getLocalGrant, upsertLocalGrant } from "@/lib/server/admin-grants-local";
import {
  deletePocketBaseUser,
  getPocketBaseAdminTokenForRequest,
  getPocketBaseUser,
  updatePocketBaseUserAccess,
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

export async function GET(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await context.params;

  if (id.startsWith("local:")) {
    const local = await getLocalGrant(id);
    if (!local) return NextResponse.json({ error: "User not found." }, { status: 404 });
    return NextResponse.json({ user: local, source: "local" });
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (!adminToken) {
    return NextResponse.json({ error: "User not found." }, { status: 404 });
  }

  const user = await getPocketBaseUser(adminToken, id);
  if (!user) {
    return NextResponse.json({ error: "User not found." }, { status: 404 });
  }

  return NextResponse.json({ user, source: "pocketbase" });
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await context.params;
  const body = await request.json().catch(() => ({}));
  const entitlement = normalizePlan(body.entitlement);
  if (!entitlement) {
    return NextResponse.json({ error: "Valid entitlement is required." }, { status: 400 });
  }

  const entitlementExpiresAt =
    body.entitlementExpiresAt === null || typeof body.entitlementExpiresAt === "string"
      ? body.entitlementExpiresAt
      : undefined;
  const adminNote =
    body.adminNote === null || typeof body.adminNote === "string" ? body.adminNote : undefined;

  if (id.startsWith("local:")) {
    const existing = await getLocalGrant(id);
    if (!existing) {
      return NextResponse.json({ error: "User not found." }, { status: 404 });
    }

    const result = await upsertLocalGrant({
      email: existing.email,
      name: existing.name,
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
  if (!adminToken) {
    return NextResponse.json({ error: "POCKETBASE_ADMIN_TOKEN is not set." }, { status: 503 });
  }

  const result = await updatePocketBaseUserAccess(adminToken, id, {
    entitlement,
    entitlementExpiresAt,
    adminNote,
  });

  if (!result.ok) {
    return NextResponse.json(
      {
        error:
          "Could not update user. Ensure PocketBase `users` has optional fields `entitlementExpiresAt` and `adminNote` (text), or remove those from the form.",
        detail: result.error,
      },
      { status: 502 }
    );
  }

  return NextResponse.json({ ok: true, user: result.user, warning: result.warning, source: "pocketbase" });
}

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  if (!(await isAdminRequest(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await context.params;

  if (id.startsWith("local:")) {
    const result = await deleteLocalGrant(id);
    if (!result.ok) {
      return NextResponse.json({ error: result.error }, { status: 404 });
    }
    return NextResponse.json({ ok: true, source: "local" });
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (!adminToken) {
    return NextResponse.json({ error: "POCKETBASE_ADMIN_TOKEN is not set." }, { status: 503 });
  }

  const existing = await getPocketBaseUser(adminToken, id);
  if (!existing) {
    return NextResponse.json({ error: "User not found." }, { status: 404 });
  }

  const deleted = await deletePocketBaseUser(adminToken, id);
  if (!deleted.ok) {
    return NextResponse.json({ error: deleted.error || "Could not delete user." }, { status: 502 });
  }

  return NextResponse.json({ ok: true, source: "pocketbase" });
}
