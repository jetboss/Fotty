import { NextResponse } from "next/server";

/** P2P/scraper bearer token — set `P2P_API_PASSWORD` in .env.local (dev) or homelab .env (prod). */
export function getP2PApiPassword(): string {
  return process.env.P2P_API_PASSWORD?.trim() || "";
}

export function p2pMisconfiguredResponse() {
  return NextResponse.json({ error: "Stream proxy is not configured." }, { status: 503 });
}

export function isP2PConfigured() {
  return Boolean(getP2PApiPassword());
}
