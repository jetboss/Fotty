export const dynamic = "force-dynamic";
import { NextResponse } from "next/server";
import { getPocketBaseUrl } from "@/lib/fotty-config";

const POCKETBASE_BASE = getPocketBaseUrl();

export async function POST(request: Request) {
  const auth = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!auth) {
    return NextResponse.json({ error: "PocketBase session required." }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const subscription = body.subscription;
  if (!subscription || typeof subscription !== "object") {
    return NextResponse.json({ error: "Push subscription payload required." }, { status: 400 });
  }

  try {
    const response = await fetch(`${POCKETBASE_BASE}/api/collections/push_subscriptions/records`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        endpoint: typeof body.endpoint === "string" ? body.endpoint : undefined,
        subscription,
        platform: "web",
        active: true,
      }),
      cache: "no-store",
    });

    if (response.ok) {
      return NextResponse.json({ ok: true, stored: true });
    }
  } catch {
    // Fall through to local-only acknowledgement.
  }

  return NextResponse.json({
    ok: true,
    stored: false,
    message: "Subscription accepted locally. Create push_subscriptions in PocketBase for cross-device delivery.",
  });
}
