import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
} from "node:crypto";
import type { FottyPlan } from "@/lib/entitlements";
import { getWatchStreamSecret } from "@/lib/server/watch-stream-secret";

export const WATCH_STREAM_TOKEN_TTL_SECONDS = 10 * 60;

export interface WatchStreamTokenPayload {
  subject: string;
  entitlement?: FottyPlan;
  nonce: string;
  exp: number;
}

function decodePayload(decoded: string): WatchStreamTokenPayload | null {
  try {
    const parsed = JSON.parse(decoded) as WatchStreamTokenPayload;
    if (!parsed?.subject || !parsed.nonce || typeof parsed.exp !== "number") return null;
    return parsed;
  } catch {
    return null;
  }
}

function encryptionKey(secret: string) {
  return createHash("sha256").update(`fotty-watch-stream-v2:${secret}`).digest();
}

export function issueWatchStreamToken(input: { email: string; userID?: string; entitlement?: FottyPlan }) {
  const secret = getWatchStreamSecret();
  if (!secret) return null;

  const normalizedIdentity = `${input.userID?.trim() || ""}|${input.email.trim().toLowerCase()}`;
  const payload: WatchStreamTokenPayload = {
    subject: createHmac("sha256", secret).update(normalizedIdentity).digest("base64url"),
    entitlement: input.entitlement,
    nonce: randomBytes(12).toString("base64url"),
    exp: Date.now() + WATCH_STREAM_TOKEN_TTL_SECONDS * 1000,
  };

  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(secret), iv);
  cipher.setAAD(Buffer.from("fotty-watch-stream-v2", "utf8"));
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(payload), "utf8"),
    cipher.final(),
  ]);
  return `v2.${iv.toString("base64url")}.${encrypted.toString("base64url")}.${cipher
    .getAuthTag()
    .toString("base64url")}`;
}

export function verifyWatchStreamToken(token: string): WatchStreamTokenPayload | null {
  const secret = getWatchStreamSecret();
  if (!secret || !token) return null;

  const [version, encodedIV, encodedBody, encodedTag] = token.split(".");
  if (version !== "v2" || !encodedIV || !encodedBody || !encodedTag) return null;
  try {
    const decipher = createDecipheriv(
      "aes-256-gcm",
      encryptionKey(secret),
      Buffer.from(encodedIV, "base64url")
    );
    decipher.setAAD(Buffer.from("fotty-watch-stream-v2", "utf8"));
    decipher.setAuthTag(Buffer.from(encodedTag, "base64url"));
    const decoded = Buffer.concat([
      decipher.update(Buffer.from(encodedBody, "base64url")),
      decipher.final(),
    ]).toString("utf8");
    const payload = decodePayload(decoded);
    if (!payload || Date.now() > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}
