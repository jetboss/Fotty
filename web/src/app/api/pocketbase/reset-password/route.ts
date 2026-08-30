export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getPocketBaseUrl } from "@/lib/fotty-config";
import { rejectIfAccountsDisabled } from "@/lib/server/accounts-disabled";

const POCKETBASE_BASE = getPocketBaseUrl();

export async function POST(request: Request) {
  const disabled = rejectIfAccountsDisabled();
  if (disabled) return disabled;

  const body = await request.json().catch(() => ({}));
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";

  if (!email) {
    return NextResponse.json({ error: "Email is required." }, { status: 400 });
  }

  try {
    const response = await fetch(`${POCKETBASE_BASE}/api/collections/users/request-password-reset`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email }),
      cache: "no-store",
    });

    if (!response.ok) {
      return NextResponse.json({ error: "Could not send reset email. Try again later." }, { status: response.status });
    }

    return NextResponse.json({
      ok: true,
      message: "If an account exists for that email, you will receive a password reset link shortly.",
    });
  } catch {
    return NextResponse.json({ error: "Password reset is temporarily unavailable." }, { status: 503 });
  }
}
