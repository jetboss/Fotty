export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { redeemQrLoginToken } from "@/lib/server/qr-login";

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token) {
    return NextResponse.json({ error: "QR login token is required." }, { status: 400 });
  }

  const result = await redeemQrLoginToken(token);
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }

  return NextResponse.json({ session: result.session, returnTo: result.returnTo });
}
