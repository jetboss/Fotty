export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { isPaidPlan, verifyCheckoutToken } from "@/lib/billing";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const email = searchParams.get("email")?.trim().toLowerCase() || "";
  const plan = searchParams.get("plan");
  const token = searchParams.get("token") || "";

  if (!email || !isPaidPlan(plan)) {
    return NextResponse.json({ error: "Invalid checkout confirmation." }, { status: 400 });
  }

  if (token && !verifyCheckoutToken(email, plan, token)) {
    return NextResponse.json({ error: "Invalid confirmation token." }, { status: 401 });
  }

  return NextResponse.json({
    ok: true,
    email,
    plan,
    verified: Boolean(token),
  });
}
