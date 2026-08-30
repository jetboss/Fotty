const buckets = new Map<string, { count: number; resetAt: number }>();

/** Simple in-memory rate limiter (per Node process). Returns true if allowed. */
export function checkRateLimit(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  const entry = buckets.get(key);

  if (!entry || now >= entry.resetAt) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }

  if (entry.count >= limit) return false;

  entry.count += 1;
  return true;
}

export function clientRateLimitKey(request: Request, prefix: string) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || request.headers.get("x-real-ip") || "unknown";
  return `${prefix}:${ip}`;
}

export function rateLimitResponse() {
  return new Response(JSON.stringify({ error: "Too many requests. Try again shortly." }), {
    status: 429,
    headers: { "Content-Type": "application/json", "Retry-After": "60" },
  });
}
