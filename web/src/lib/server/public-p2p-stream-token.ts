import { createHmac, randomUUID } from "node:crypto";
import { getP2PApiPassword } from "@/lib/server-env";
import { getWatchStreamSecret } from "@/lib/server/watch-stream-secret";

const TOKEN_TTL_MS = Number(process.env.P2P_PUBLIC_STREAM_TOKEN_TTL_MS || 30 * 60 * 1000);

function streamTokenSecret() {
  return (
    process.env.P2P_PUBLIC_STREAM_TOKEN_SECRET?.trim() ||
    getP2PApiPassword() ||
    getWatchStreamSecret()
  );
}

export function issuePublicP2PStreamToken(cid: string) {
  const secret = streamTokenSecret();
  const normalizedCID = cid.trim();
  if (!secret || !normalizedCID) return null;

  const payload = {
    cid: normalizedCID,
    exp: Math.floor((Date.now() + TOKEN_TTL_MS) / 1000),
    nonce: randomUUID(),
  };
  const body = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  const sig = createHmac("sha256", secret).update(body).digest("base64url");
  return `${body}.${sig}`;
}
