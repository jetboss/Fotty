"use client";

import { useState } from "react";
import { Check, Copy, UserPlus } from "lucide-react";
import type { FottyPlan } from "@/lib/entitlements";
import type { AdminUser } from "@/components/admin/admin-types";
import {
  presetExpiryInputValue,
  presetToAccess,
  type EntitlementPreset,
} from "@/lib/entitlement-access";

const PLAN_OPTIONS: { value: FottyPlan; label: string }[] = [
  { value: "free", label: "Free" },
  { value: "supporter", label: "Match-Day Pass" },
  { value: "plus", label: "Fotty Plus" },
  { value: "builder", label: "Fotty Builder" },
  { value: "collab", label: "Fotty Collab" },
];

const ACCESS_PRESETS: { id: EntitlementPreset; label: string }[] = [
  { id: "matchday", label: "7 days" },
  { id: "monthly", label: "30 days" },
  { id: "annual", label: "1 year" },
  { id: "lifetime", label: "Lifetime" },
];

interface AdminCreateUserPanelProps {
  mode: "pocketbase" | "local";
  onCreated: (user: AdminUser, credentials?: { email: string; password: string }) => void;
  onError: (message: string) => void;
}

export function AdminCreateUserPanel({ mode, onCreated, onError }: AdminCreateUserPanelProps) {
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [entitlement, setEntitlement] = useState<FottyPlan>("plus");
  const [expiresAt, setExpiresAt] = useState("");
  const [adminNote, setAdminNote] = useState("");
  const [customPassword, setCustomPassword] = useState("");
  const [useCustomPassword, setUseCustomPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [credentials, setCredentials] = useState<{ email: string; password: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  async function handleSubmit() {
    const trimmedEmail = email.trim().toLowerCase();
    if (!trimmedEmail) {
      onError("Email is required.");
      return;
    }

    setIsSubmitting(true);
    onError("");
    setNotice(null);
    setCredentials(null);

    try {
      const response = await fetch("/api/admin/users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: trimmedEmail,
          name: name.trim() || undefined,
          source: mode,
          entitlement,
          entitlementExpiresAt: expiresAt ? new Date(expiresAt).toISOString() : null,
          adminNote: adminNote.trim() || null,
          password: useCustomPassword ? customPassword : undefined,
        }),
      });

      const payload = (await response.json()) as {
        user?: AdminUser;
        temporaryPassword?: string;
        error?: string;
        warning?: string;
      };

      if (!response.ok) {
        onError(payload.error || "Could not create account.");
        return;
      }

      if (!payload.user) {
        onError("Account created but response was incomplete.");
        return;
      }

      const nextCredentials =
        mode === "pocketbase" && payload.temporaryPassword
          ? { email: trimmedEmail, password: payload.temporaryPassword }
          : useCustomPassword && customPassword.trim()
            ? { email: trimmedEmail, password: customPassword.trim() }
            : null;

      if (nextCredentials) setCredentials(nextCredentials);

      setEmail("");
      setName("");
      setExpiresAt("");
      setAdminNote("");
      setCustomPassword("");
      setUseCustomPassword(false);

      onCreated(payload.user, nextCredentials ?? undefined);
      if (payload.warning) setNotice(payload.warning);
    } catch {
      onError("Create request failed.");
    } finally {
      setIsSubmitting(false);
    }
  }

  async function copyCredentials() {
    if (!credentials) return;
    const text = `Fotty login\nEmail: ${credentials.email}\nPassword: ${credentials.password}\n\nSign in at your Fotty link, then you can watch live streams.`;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      onError("Could not copy — select and copy manually.");
    }
  }

  return (
    <section className="space-y-3 rounded-lg border border-accent/20 bg-accent/5 p-4">
      <div className="flex items-start gap-3">
        <UserPlus size={18} className="mt-0.5 shrink-0 text-accent" />
        <div className="min-w-0 space-y-1">
          <p className="text-sm font-black text-white">Create account</p>
          <p className="text-xs font-medium leading-5 text-text-secondary">
            {mode === "pocketbase"
              ? "Creates a real login in PocketBase. Send the one-time password on WhatsApp, then they can sign in and watch."
              : "Local grant only (no login). Connect PocketBase for full accounts."}
          </p>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <label className="block space-y-1.5 sm:col-span-2">
          <span className="text-[11px] font-bold uppercase text-text-tertiary">Email</span>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="customer@example.com"
            className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
          />
        </label>

        <label className="block space-y-1.5">
          <span className="text-[11px] font-bold uppercase text-text-tertiary">Name (optional)</span>
          <input
            type="text"
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Display name"
            className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
          />
        </label>

        <label className="block space-y-1.5">
          <span className="text-[11px] font-bold uppercase text-text-tertiary">Plan</span>
          <select
            value={entitlement}
            onChange={(event) => setEntitlement(event.target.value as FottyPlan)}
            className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
          >
            {PLAN_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>

        <div className="space-y-1.5 sm:col-span-2">
          <span className="text-[11px] font-bold uppercase text-text-tertiary">Quick expiry</span>
          <div className="flex flex-wrap gap-2">
            {ACCESS_PRESETS.map((preset) => (
              <button
                key={preset.id}
                type="button"
                onClick={() => {
                  const access = presetToAccess(preset.id);
                  setEntitlement(access.entitlement);
                  setExpiresAt(presetExpiryInputValue(preset.id));
                }}
                className="rounded-full border border-white/10 bg-background px-2.5 py-1 text-[10px] font-bold text-text-secondary hover:text-white"
              >
                {preset.label}
              </button>
            ))}
          </div>
        </div>

        <label className="block space-y-1.5">
          <span className="text-[11px] font-bold uppercase text-text-tertiary">Expires (optional)</span>
          <input
            type="date"
            value={expiresAt}
            onChange={(event) => setExpiresAt(event.target.value)}
            className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
          />
        </label>

        <label className="block space-y-1.5 sm:col-span-2">
          <span className="text-[11px] font-bold uppercase text-text-tertiary">Admin note</span>
          <input
            type="text"
            value={adminNote}
            onChange={(event) => setAdminNote(event.target.value)}
            placeholder="WhatsApp payment ref…"
            className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
          />
        </label>

        {mode === "pocketbase" ? (
          <div className="space-y-2 sm:col-span-2">
            <label className="flex items-center gap-2 text-xs font-medium text-text-secondary">
              <input
                type="checkbox"
                checked={useCustomPassword}
                onChange={(event) => setUseCustomPassword(event.target.checked)}
                className="rounded border-white/20"
              />
              Set password manually (otherwise auto-generated)
            </label>
            {useCustomPassword ? (
              <input
                type="text"
                value={customPassword}
                onChange={(event) => setCustomPassword(event.target.value)}
                placeholder="Min 8 characters"
                className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
              />
            ) : null}
          </div>
        ) : null}
      </div>

      <button
        type="button"
        disabled={isSubmitting || !email.trim()}
        onClick={() => void handleSubmit()}
        className="inline-flex min-h-10 w-full items-center justify-center rounded-lg accent-gradient px-4 text-xs font-black text-white disabled:opacity-50 sm:w-auto"
      >
        {isSubmitting ? "Creating…" : mode === "pocketbase" ? "Create account" : "Add grant"}
      </button>

      {notice ? <p className="text-xs font-medium text-warning">{notice}</p> : null}

      {credentials ? (
        <div className="rounded-lg border border-success/30 bg-success/10 p-3">
          <p className="text-xs font-bold text-success">Account ready — send these details once</p>
          <p className="mt-2 break-all font-mono text-xs text-white">
            {credentials.email}
            <br />
            {credentials.password}
          </p>
          <button
            type="button"
            onClick={() => void copyCredentials()}
            className="mt-3 inline-flex items-center gap-2 rounded-full border border-white/10 bg-black/30 px-3 py-1.5 text-[11px] font-bold text-white"
          >
            {copied ? <Check size={13} /> : <Copy size={13} />}
            {copied ? "Copied" : "Copy for WhatsApp"}
          </button>
        </div>
      ) : null}
    </section>
  );
}
