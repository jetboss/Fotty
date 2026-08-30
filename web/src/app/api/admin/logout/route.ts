export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { adminCookieName } from "@/lib/server/admin-auth";

export async function POST() {
  const response = NextResponse.json({ ok: true });
  response.cookies.set(adminCookieName(), "", { path: "/", maxAge: 0 });
  return response;
}
