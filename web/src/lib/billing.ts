import { createHmac, timingSafeEqual } from "node:crypto";
import type { PaidPlan } from "@/lib/billing-plans";

export { isPaidPlan } from "@/lib/billing-plans";
export type { PaidPlan } from "@/lib/billing-plans";

export function getBillingWebhookSecret() {
  return process.env.FOTTY_BILLING_WEBHOOK_SECRET?.trim() || "";
}

export function signCheckoutToken(email: string, plan: PaidPlan) {
  const secret = getBillingWebhookSecret();
  if (!secret) return "";
  return createHmac("sha256", secret).update(`${email.toLowerCase()}:${plan}`).digest("hex");
}

export function verifyCheckoutToken(email: string, plan: PaidPlan, token: string) {
  const expected = signCheckoutToken(email, plan);
  if (!expected || !token) return false;

  try {
    const left = Buffer.from(expected, "utf8");
    const right = Buffer.from(token, "utf8");
    return left.length === right.length && timingSafeEqual(left, right);
  } catch {
    return false;
  }
}

export function appendCheckoutSuccessUrl(checkoutUrl: string, email: string, plan: PaidPlan, siteUrl: string) {
  const url = new URL(checkoutUrl);
  const success = new URL("/subscribe/success", siteUrl);
  success.searchParams.set("plan", plan);
  success.searchParams.set("email", email);

  const token = signCheckoutToken(email, plan);
  if (token) success.searchParams.set("token", token);

  url.searchParams.set("success_url", success.toString());
  url.searchParams.set("cancel_url", `${siteUrl}/subscribe`);
  return url.toString();
}
