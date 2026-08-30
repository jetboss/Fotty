/** True when the P2P proxy reports a session that can serve HLS (not merely warming). */
export function isP2PSessionActive(telemetry?: {
  status?: string;
  isLive?: boolean;
}): boolean {
  const status = telemetry?.status?.trim().toLowerCase();
  return status === "active" || status === "ready" || Boolean(telemetry?.isLive);
}
