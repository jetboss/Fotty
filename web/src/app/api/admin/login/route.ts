export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import {
  adminCookieName,
  adminCookieOptions,
  createAdminSessionToken,
  getAdminPassword,
  isAdminConfigured,
} from "@/lib/server/admin-auth";
import { checkRateLimit, clientRateLimitKey, rateLimitResponse } from "@/lib/server/rate-limit";

const ADMIN_LOGIN_LIMIT = 8;
const ADMIN_LOGIN_WINDOW_MS = 15 * 60_000;

export async function POST(request: Request) {
  if (!isAdminConfigured()) {
    return NextResponse.json(
      { error: "Admin dashboard is not configured. Set FOTTY_ADMIN_PASSWORD." },
      { status: 503 }
    );
  }

  if (!checkRateLimit(clientRateLimitKey(request, "admin-login"), ADMIN_LOGIN_LIMIT, ADMIN_LOGIN_WINDOW_MS)) {
    return rateLimitResponse();
  }

  const body = await request.json().catch(() => ({}));
  const password = typeof body.password === "string" ? body.password : "";

  if (password !== getAdminPassword()) {
    return NextResponse.json({ error: "Invalid password." }, { status: 401 });
  }

  const response = NextResponse.json({ ok: true });
  response.cookies.set(adminCookieName(), await createAdminSessionToken(), adminCookieOptions());
  return response;
}
