"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Lock } from "lucide-react";
import { AdminPageShell } from "@/components/admin/AdminPageShell";

export interface AdminLoginDevHints {
  adminPassword: string | null;
  pocketBaseEmail: string | null;
  pocketBasePassword: string | null;
  pocketBaseAdminUrl: string | null;
  credsFile: string;
}

export function AdminLoginForm({ devHints }: { devHints: AdminLoginDevHints | null }) {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [showHints, setShowHints] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const payload = (await response.json().catch(() => ({}))) as { error?: string };
      if (!response.ok) {
        setError(payload.error || "Login failed.");
        return;
      }
      router.replace("/admin");
      router.refresh();
    } catch {
      setError("Could not reach the server.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <AdminPageShell className="flex min-h-dvh flex-col justify-center px-4 py-12 sm:px-6">
      <main className="mx-auto w-full max-w-md space-y-4">
        <div className="rounded-2xl border border-white/10 bg-surface p-6 shadow-xl">
          <div className="mb-6 space-y-2 text-center">
            <div className="mx-auto grid h-12 w-12 place-items-center rounded-full bg-accent/15 text-accent">
              <Lock size={22} />
            </div>
            <h1 className="text-2xl font-black text-white">Fotty admin</h1>
            <p className="text-sm font-medium text-text-secondary">
              Grant plans, expiry, and notes after WhatsApp payments.
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <label className="block space-y-2">
              <span className="text-xs font-bold uppercase text-text-tertiary">Password</span>
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete="current-password"
                className="w-full rounded-lg border border-white/10 bg-background px-4 py-3 text-sm font-medium text-text-primary outline-none focus:border-accent/40"
                placeholder="Enter admin password"
              />
            </label>

            {error ? <p className="text-xs font-medium text-error">{error}</p> : null}

            <button
              type="submit"
              disabled={isLoading || !password}
              className="inline-flex min-h-11 w-full items-center justify-center rounded-lg accent-gradient px-4 text-sm font-black text-white disabled:opacity-60"
            >
              {isLoading ? "Signing in…" : "Open dashboard"}
            </button>
          </form>

          <p className="mt-6 text-center text-xs text-text-tertiary">
            <Link href="/" className="font-bold text-accent hover:underline">
              Back to Fotty
            </Link>
          </p>
        </div>

        {devHints ? (
          <section className="rounded-xl border border-white/10 bg-surface/80 p-4 text-xs text-text-secondary">
            <button
              type="button"
              onClick={() => setShowHints((open) => !open)}
              className="w-full text-left font-bold text-text-primary"
            >
              {showHints ? "Hide" : "Show"} local credentials
            </button>
            {showHints ? (
              <ul className="mt-3 space-y-2 leading-5">
                <li>
                  <strong className="text-text-primary">This page password</strong> —{" "}
                  <code className="text-accent">web/.env.local</code> →{" "}
                  <code className="text-accent">FOTTY_ADMIN_PASSWORD</code>
                  {devHints.adminPassword ? (
                    <>
                      <br />
                      <span className="mt-1 inline-block rounded bg-background px-2 py-1 font-mono text-[11px] text-white">
                        {devHints.adminPassword}
                      </span>
                    </>
                  ) : (
                    <span className="text-warning"> (not set — add one and restart dev)</span>
                  )}
                </li>
                <li>
                  <strong className="text-text-primary">PocketBase</strong> — retired with the homelab. Leave unset unless
                  you are testing a temporary host.
                  {devHints.pocketBaseEmail || devHints.pocketBaseAdminUrl ? (
                    <>
                      <br />
                      Optional local file: <code className="text-accent">{devHints.credsFile}</code>
                      {devHints.pocketBaseEmail ? (
                        <>
                          <br />
                          Email: <code className="text-accent">{devHints.pocketBaseEmail}</code>
                        </>
                      ) : null}
                      {devHints.pocketBaseAdminUrl ? (
                        <>
                          <br />
                          Admin UI:{" "}
                          <a
                            href={devHints.pocketBaseAdminUrl}
                            className="text-accent underline"
                            target="_blank"
                            rel="noreferrer"
                          >
                            {devHints.pocketBaseAdminUrl}
                          </a>
                        </>
                      ) : null}
                    </>
                  ) : null}
                </li>
              </ul>
            ) : null}
          </section>
        ) : null}
      </main>
    </AdminPageShell>
  );
}

