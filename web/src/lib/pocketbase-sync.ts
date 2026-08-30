"use client";

import { getAuthSession } from "./auth";

type PocketBaseSyncType = "teamFollow" | "matchReminder" | "collabInquiry" | "supportPledge";

interface SyncResult {
  ok: boolean;
  status: string;
  statusCode?: number;
}

export async function syncPocketBaseRecord(type: PocketBaseSyncType, data: object): Promise<SyncResult> {
  const session = getAuthSession();
  if (!session?.token || !session.userID) {
    return { ok: false, status: "missing_session" };
  }

  try {
    const response = await fetch("/api/pocketbase/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        type,
        token: session.token,
        userID: session.userID,
        data,
      }),
    });

    const result = await response.json().catch(() => ({}));
    return {
      ok: response.ok && result.ok !== false,
      status: result.status || (response.ok ? "synced" : "failed"),
      statusCode: response.status,
    };
  } catch {
    return { ok: false, status: "unavailable" };
  }
}

export function syncPocketBaseRecordLater(type: PocketBaseSyncType, data: object) {
  void syncPocketBaseRecord(type, data);
}
