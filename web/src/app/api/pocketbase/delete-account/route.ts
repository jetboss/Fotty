export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getPocketBaseUrl } from "@/lib/fotty-config";
import { deletePocketBaseUser, getPocketBaseAdminTokenForRequest } from "@/lib/server/pocketbase-admin";
import { findUserIDByEmail } from "@/lib/server/pocketbase-user";
import { pocketBaseUserMessage } from "@/lib/server/pocketbase-errors";
import { rejectIfAccountsDisabled } from "@/lib/server/accounts-disabled";

const POCKETBASE_BASE = getPocketBaseUrl();

export async function POST(request: Request) {
  const disabled = rejectIfAccountsDisabled();
  if (disabled) return disabled;

  const body = await request.json().catch(() => ({}));
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const confirm = typeof body.confirm === "string" ? body.confirm.trim() : "";

  if (!email || !password) {
    return NextResponse.json({ error: "Email and password are required." }, { status: 400 });
  }

  if (confirm !== "DELETE") {
    return NextResponse.json({ error: 'Type DELETE in the confirmation field to continue.' }, { status: 400 });
  }

  const adminToken = await getPocketBaseAdminTokenForRequest();
  if (!adminToken) {
    return NextResponse.json({ error: "Account deletion is not configured on this server." }, { status: 503 });
  }

  try {
    const authResponse = await fetch(`${POCKETBASE_BASE}/api/collections/users/auth-with-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ identity: email, password }),
      cache: "no-store",
    });

    if (!authResponse.ok) {
      const errorPayload = await authResponse.json().catch(() => ({}));
      const message = pocketBaseUserMessage(errorPayload, "Invalid email or password.");
      return NextResponse.json({ error: message }, { status: 401 });
    }

    const authPayload = (await authResponse.json()) as { record?: { id?: string } };
    const userID = authPayload.record?.id || (await findUserIDByEmail(email, adminToken));
    if (!userID) {
      return NextResponse.json({ error: "Account not found." }, { status: 404 });
    }

    const deleted = await deletePocketBaseUser(adminToken, userID);
    if (!deleted.ok) {
      return NextResponse.json({ error: deleted.error || "Could not delete account." }, { status: 502 });
    }

    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: "Account deletion is temporarily unavailable." }, { status: 503 });
  }
}
