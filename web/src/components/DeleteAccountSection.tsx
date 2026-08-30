"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, Loader2 } from "lucide-react";
import { useAuth } from "@/components/AuthProvider";
import { deleteAccount } from "@/lib/auth";

export function DeleteAccountSection() {
  const { session } = useAuth();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (!session?.email || session.provider === "local") {
    return null;
  }

  async function handleDelete() {
    setError(null);
    setBusy(true);
    try {
      await deleteAccount(password, confirm);
      setOpen(false);
      router.replace("/");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not delete account.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="space-y-3">
      <h2 className="px-1 text-xs font-bold text-danger">Danger zone</h2>
      <div className="overflow-hidden rounded-lg border border-danger/30 bg-danger/5">
        {!open ? (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="flex w-full items-center gap-4 p-4 text-left"
          >
            <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-danger/15 text-danger">
              <AlertTriangle size={18} />
            </div>
            <div className="min-w-0">
              <h3 className="text-sm font-semibold text-danger">Delete account</h3>
              <p className="text-xs text-text-tertiary">
                Permanently remove your Fotty sign-in and cloud access. This cannot be undone.
              </p>
            </div>
          </button>
        ) : (
          <div className="space-y-4 p-4">
            <p className="text-xs font-medium leading-5 text-text-secondary">
              Your PocketBase account and paid access on our servers will be removed. Saved reminders and favorites on
              this device stay until you clear site data.
            </p>
            <label className="block space-y-1">
              <span className="text-xs font-bold text-text-tertiary">Password</span>
              <input
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm text-white"
              />
            </label>
            <label className="block space-y-1">
              <span className="text-xs font-bold text-text-tertiary">Type DELETE to confirm</span>
              <input
                type="text"
                autoComplete="off"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm text-white"
                placeholder="DELETE"
              />
            </label>
            {error && <p className="text-xs font-medium text-danger">{error}</p>}
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                disabled={busy || !password || confirm !== "DELETE"}
                onClick={() => void handleDelete()}
                className="inline-flex items-center gap-2 rounded-full bg-danger px-4 py-2 text-xs font-bold text-white disabled:opacity-50"
              >
                {busy && <Loader2 size={14} className="animate-spin" />}
                Delete my account
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => {
                  setOpen(false);
                  setPassword("");
                  setConfirm("");
                  setError(null);
                }}
                className="rounded-full bg-white/10 px-4 py-2 text-xs font-bold text-white"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
