export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { appendCheckoutSuccessUrl, isPaidPlan } from "@/lib/billing";
import { getSiteUrl } from "@/lib/fotty-config";

const CHECKOUT_BY_PLAN: Record<string, string | undefined> = {
  plus: process.env.NEXT_PUBLIC_PLUS_CHECKOUT_URL,
  supporter: process.env.NEXT_PUBLIC_SUPPORT_MONTHLY_URL,
  collab: process.env.NEXT_PUBLIC_COLLAB_CHECKOUT_URL || process.env.NEXT_PUBLIC_SUPPORT_PARTNER_URL,
};

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const plan = searchParams.get("plan");
  const email = searchParams.get("email")?.trim().toLowerCase() || "";

  if (!isPaidPlan(plan)) {
    return NextResponse.json({ error: "Valid paid plan required." }, { status: 400 });
  }

  const base = CHECKOUT_BY_PLAN[plan]?.trim();
  if (!base) {
    return NextResponse.json({ error: "Checkout URL is not configured for this plan." }, { status: 404 });
  }

  let url = base;
  if (email) {
    url = appendCheckoutSuccessUrl(base, email, plan, getSiteUrl());
  } else {
    const checkout = new URL(base);
    checkout.searchParams.set("success_url", new URL("/subscribe/success", getSiteUrl()).toString());
    checkout.searchParams.set("cancel_url", `${getSiteUrl()}/subscribe`);
    url = checkout.toString();
  }

  return NextResponse.json({ url, plan });
}
