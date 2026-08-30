"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { LucideIcon } from "lucide-react";
import { AlertTriangle, Check, Clock3, Copy, LogOut, QrCode, RefreshCw, Search, Shield, Sparkles, Users } from "lucide-react";
import { AdminPageShell } from "@/components/admin/AdminPageShell";
import { AdminCreateUserPanel } from "@/components/admin/AdminCreateUserPanel";
import { AdminSetupBanner } from "@/components/admin/AdminSetupBanner";
import type { AdminUser } from "@/components/admin/admin-types";
import type { FottyPlan } from "@/lib/entitlements";
import {
  formatExpiryDate,
  presetExpiryInputValue,
  presetToAccess,
  type EntitlementPreset,
} from "@/lib/entitlement-access";
import { buildWhatsAppPayUrl } from "@/lib/tt-plans";
import type { TtCheckoutPlanId } from "@/lib/tt-plans";
import { cn } from "@/lib/utils";

const PLAN_OPTIONS: { value: FottyPlan; label: string }[] = [
  { value: "free", label: "Free" },
  { value: "supporter", label: "Match-Day Pass (supporter)" },
  { value: "plus", label: "Fotty Plus" },
  { value: "builder", label: "Fotty Builder" },
  { value: "collab", label: "Fotty Collab" },
];

const WHATSAPP_PLAN_HINT: Partial<Record<FottyPlan, TtCheckoutPlanId>> = {
  supporter: "supporter",
  plus: "plus_annual",
  builder: "builder",
  collab: "collab",
};

const ACCESS_PRESETS: { id: EntitlementPreset; label: string }[] = [
  { id: "matchday", label: "Match-Day · 7 days" },
  { id: "monthly", label: "Plus · 30 days" },
  { id: "annual", label: "Plus · 1 year" },
  { id: "lifetime", label: "Plus · lifetime" },
];

type AccessFilter = "all" | "active" | "expiring" | "expired" | "lifetime" | "matchday" | "plus" | "free";

const ACCESS_FILTERS: { id: AccessFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "active", label: "Active" },
  { id: "expiring", label: "Expiring" },
  { id: "expired", label: "Expired" },
  { id: "lifetime", label: "Lifetime" },
  { id: "matchday", label: "Match-Day" },
  { id: "plus", label: "Plus" },
  { id: "free", label: "Free" },
];

function getDaysUntil(value?: string | null) {
  if (!value) return null;
  const expiry = new Date(value).getTime();
  if (!Number.isFinite(expiry)) return null;
  return Math.ceil((expiry - Date.now()) / 86_400_000);
}

function getAccessMeta(user: AdminUser) {
  const daysUntil = getDaysUntil(user.entitlementExpiresAt);
  const hasPaidPlan = user.entitlement !== "free";
  const isLifetime = hasPaidPlan && !user.entitlementExpiresAt;
  const isExpired = hasPaidPlan && daysUntil !== null && daysUntil < 0;
  const isExpiring = hasPaidPlan && daysUntil !== null && daysUntil >= 0 && daysUntil <= 7;
  const isActive = hasPaidPlan && !isExpired;
  const label = user.entitlement === "free"
    ? "Free"
    : isLifetime
      ? "Lifetime"
      : isExpired
        ? "Expired"
        : isExpiring
          ? `${daysUntil === 0 ? "Today" : `${daysUntil}d left`}`
          : "Active";
  const tone = user.entitlement === "free"
    ? "neutral"
    : isLifetime
      ? "lifetime"
      : isExpired
        ? "expired"
        : isExpiring
          ? "expiring"
          : "active";

  return { daysUntil, isLifetime, isExpired, isExpiring, isActive, label, tone };
}

function matchesAccessFilter(user: AdminUser, filter: AccessFilter) {
  const meta = getAccessMeta(user);
  switch (filter) {
    case "active":
      return meta.isActive;
    case "expiring":
      return meta.isExpiring;
    case "expired":
      return meta.isExpired;
    case "lifetime":
      return meta.isLifetime;
    case "matchday":
      return user.entitlement === "supporter";
    case "plus":
      return user.entitlement === "plus";
    case "free":
      return user.entitlement === "free";
    case "all":
    default:
      return true;
  }
}

export function AdminAccessDashboard() {
  const [query, setQuery] = useState("");
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const [accessFilter, setAccessFilter] = useState<AccessFilter>("all");
  const [page, setPage] = useState(1);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [totalPages, setTotalPages] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<AdminUser | null>(null);
  const [entitlement, setEntitlement] = useState<FottyPlan>("free");
  const [expiresAt, setExpiresAt] = useState("");
  const [adminNote, setAdminNote] = useState("");
  const [saveMessage, setSaveMessage] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [deleteConfirmEmail, setDeleteConfirmEmail] = useState("");
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [userSource, setUserSource] = useState<"local" | "pocketbase" | null>(null);
  const [userListWarning, setUserListWarning] = useState<string | null>(null);
  const [createError, setCreateError] = useState<string | null>(null);
  const [loginLink, setLoginLink] = useState<{ url: string; expiresAt: string; email: string } | null>(null);
  const [isGeneratingLoginLink, setIsGeneratingLoginLink] = useState(false);
  const [loginLinkCopied, setLoginLinkCopied] = useState(false);

  useEffect(() => {
    const id = window.setTimeout(() => setDebouncedQuery(query.trim()), 300);
    return () => window.clearTimeout(id);
  }, [query]);

  const loadUsers = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    setUserListWarning(null);
    try {
      const params = new URLSearchParams({ page: String(page) });
      if (debouncedQuery) params.set("q", debouncedQuery);
      const response = await fetch(`/api/admin/users?${params.toString()}`, { cache: "no-store" });
      const payload = (await response.json()) as {
        items?: AdminUser[];
        totalPages?: number;
        error?: string;
        warning?: string;
        source?: "local" | "pocketbase";
      };
      if (!response.ok) {
        setError(payload.error || "Failed to load users.");
        setUsers([]);
        setUserSource(null);
        setUserListWarning(null);
        return;
      }
      setUsers(payload.items ?? []);
      setTotalPages(Math.max(1, payload.totalPages ?? 1));
      setUserSource(payload.source ?? null);
      setUserListWarning(payload.warning ?? null);
    } catch {
      setError("Could not load users.");
      setUserListWarning(null);
    } finally {
      setIsLoading(false);
    }
  }, [debouncedQuery, page]);

  useEffect(() => {
    void loadUsers();
  }, [loadUsers]);

  useEffect(() => {
    setPage(1);
  }, [debouncedQuery]);

  useEffect(() => {
    if (!selected) return;
    setEntitlement(selected.entitlement);
    setExpiresAt(selected.entitlementExpiresAt?.slice(0, 10) ?? "");
    setAdminNote(selected.adminNote ?? "");
    setSaveMessage(null);
    setLoginLink(null);
    setLoginLinkCopied(false);
  }, [selected]);

  function applyPreset(preset: EntitlementPreset) {
    const access = presetToAccess(preset);
    setEntitlement(access.entitlement);
    setExpiresAt(presetExpiryInputValue(preset));
  }

  async function handleSave() {
    if (!selected) return;
    setIsSaving(true);
    setSaveMessage(null);
    try {
      const response = await fetch(`/api/admin/users/${selected.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          entitlement,
          entitlementExpiresAt: expiresAt ? new Date(expiresAt).toISOString() : null,
          adminNote: adminNote.trim() || null,
        }),
      });
      const payload = (await response.json()) as { user?: AdminUser; warning?: string; error?: string };
      if (!response.ok) {
        setSaveMessage(payload.error || "Save failed.");
        return;
      }
      const updated = payload.user;
      if (updated) {
        setSelected(updated);
        setUsers((prev) => prev.map((row) => (row.id === updated.id ? { ...row, ...updated } : row)));
      }
      setSaveMessage(payload.warning ? `Saved with note: ${payload.warning}` : "Access updated.");
      window.dispatchEvent(new CustomEvent("fotty:admin-status-refresh"));
    } catch {
      setSaveMessage("Save request failed.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleDelete() {
    if (!selected) return;
    if (deleteConfirmEmail.trim().toLowerCase() !== selected.email.trim().toLowerCase()) {
      setSaveMessage("Type the account email exactly to confirm deletion.");
      return;
    }

    setIsDeleting(true);
    setSaveMessage(null);
    try {
      const response = await fetch(`/api/admin/users/${selected.id}`, { method: "DELETE" });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) {
        setSaveMessage(payload.error || "Delete failed.");
        return;
      }
      setUsers((prev) => prev.filter((row) => row.id !== selected.id));
      setSelected(null);
      setShowDeleteConfirm(false);
      setDeleteConfirmEmail("");
      setSaveMessage("Account deleted.");
      window.dispatchEvent(new CustomEvent("fotty:admin-status-refresh"));
    } catch {
      setSaveMessage("Delete request failed.");
    } finally {
      setIsDeleting(false);
    }
  }

  async function handleLogout() {
    await fetch("/api/admin/logout", { method: "POST" });
    window.location.href = "/admin/login";
  }

  async function handleGenerateLoginLink() {
    if (!selected) return;
    setIsGeneratingLoginLink(true);
    setSaveMessage(null);
    setLoginLinkCopied(false);
    try {
      const response = await fetch("/api/admin/login-links", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ userID: selected.id, returnTo: "/" }),
      });
      const payload = (await response.json().catch(() => ({}))) as {
        url?: string;
        expiresAt?: string;
        email?: string;
        error?: string;
      };
      if (!response.ok || !payload.url || !payload.expiresAt || !payload.email) {
        setSaveMessage(payload.error || "Could not create QR login.");
        return;
      }
      setLoginLink({ url: payload.url, expiresAt: payload.expiresAt, email: payload.email });
      setSaveMessage("QR login ready.");
    } catch {
      setSaveMessage("QR login request failed.");
    } finally {
      setIsGeneratingLoginLink(false);
    }
  }

  async function copyLoginLink() {
    if (!loginLink) return;
    try {
      await navigator.clipboard.writeText(loginLink.url);
      setLoginLinkCopied(true);
      window.setTimeout(() => setLoginLinkCopied(false), 2000);
    } catch {
      setSaveMessage("Could not copy QR login link.");
    }
  }

  const whatsappPlan = WHATSAPP_PLAN_HINT[entitlement];
  const whatsappHref =
    selected && whatsappPlan ? buildWhatsAppPayUrl(whatsappPlan, { email: selected.email }) : null;
  const visibleUsers = useMemo(() => {
    const localQuery = debouncedQuery.toLowerCase();
    return users.filter((user) => {
      if (!matchesAccessFilter(user, accessFilter)) return false;
      if (!localQuery) return true;
      return (
        user.email.toLowerCase().includes(localQuery) ||
        (user.adminNote || "").toLowerCase().includes(localQuery) ||
        user.entitlement.toLowerCase().includes(localQuery)
      );
    });
  }, [accessFilter, debouncedQuery, users]);
  const summary = useMemo(() => {
    const paid = users.filter((user) => user.entitlement !== "free");
    return {
      active: paid.filter((user) => getAccessMeta(user).isActive).length,
      expiring: paid.filter((user) => getAccessMeta(user).isExpiring).length,
      expired: paid.filter((user) => getAccessMeta(user).isExpired).length,
      lifetime: paid.filter((user) => getAccessMeta(user).isLifetime).length,
      matchday: users.filter((user) => user.entitlement === "supporter").length,
      total: users.length,
    };
  }, [users]);
  const selectedMeta = selected ? getAccessMeta(selected) : null;

  return (
    <AdminPageShell className="pb-20 pt-6 sm:pt-8">
      <main className="mx-auto w-full max-w-6xl space-y-6 px-4 sm:px-6">
        <header className="flex flex-wrap items-start justify-between gap-4">
          <div className="space-y-1">
            <p className="text-xs font-bold uppercase tracking-wide text-accent">Fotty admin</p>
            <h1 className="text-3xl font-black text-white">Access dashboard</h1>
            <p className="max-w-2xl text-sm font-medium text-text-secondary">
              Create logins, set plans after WhatsApp + bank transfer, and copy credentials to send customers.
              {userSource === "local"
                ? " Saving to web/.data/admin-grants.json until PocketBase is connected."
                : " Accounts and plans sync to PocketBase."}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => void loadUsers()}
              className="inline-flex h-10 items-center gap-2 rounded-full border border-white/10 bg-surface px-4 text-xs font-bold"
            >
              <RefreshCw size={14} />
              Refresh
            </button>
            <button
              type="button"
              onClick={() => void handleLogout()}
              className="inline-flex h-10 items-center gap-2 rounded-full border border-white/10 bg-surface px-4 text-xs font-bold text-text-secondary"
            >
              <LogOut size={14} />
              Sign out
            </button>
          </div>
        </header>

        <AdminSetupBanner />

        <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <SummaryCard icon={Users} label="Visible accounts" value={`${summary.total}`} />
          <SummaryCard icon={Shield} label="Active access" value={`${summary.active}`} tone="active" />
          <SummaryCard icon={Clock3} label="Expiring soon" value={`${summary.expiring}`} tone="expiring" />
          <SummaryCard icon={AlertTriangle} label="Expired" value={`${summary.expired}`} tone="expired" />
          <SummaryCard icon={Sparkles} label="Lifetime" value={`${summary.lifetime}`} tone="lifetime" />
        </section>

        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
          <section className="space-y-4 rounded-xl border border-white/5 bg-surface p-4">
            <AdminCreateUserPanel
              mode={userSource === "pocketbase" ? "pocketbase" : "local"}
              onError={(message) => setCreateError(message || null)}
              onCreated={(user) => {
                setCreateError(null);
                setSelected(user);
                setSaveMessage(userSource === "pocketbase" ? "Account created." : "Grant saved.");
                void loadUsers();
              }}
            />

            {createError ? <p className="text-sm font-medium text-error">{createError}</p> : null}

            <div className="relative">
              <Search size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-tertiary" />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search by email, note, or plan…"
                className="w-full rounded-lg border border-white/10 bg-background py-2.5 pl-9 pr-3 text-sm font-medium outline-none focus:border-accent/40"
              />
            </div>

            <div className="flex flex-wrap gap-2">
              {ACCESS_FILTERS.map((filter) => (
                <button
                  key={filter.id}
                  type="button"
                  onClick={() => setAccessFilter(filter.id)}
                  className={cn(
                    "rounded-full border px-3 py-1.5 text-[11px] font-black transition-colors",
                    accessFilter === filter.id
                      ? "border-accent/40 bg-accent/15 text-white"
                      : "border-white/10 bg-background text-text-secondary hover:border-white/20 hover:text-white"
                  )}
                >
                  {filter.label}
                </button>
              ))}
            </div>

            {error ? <p className="text-sm font-medium text-error">{error}</p> : null}
            {userListWarning ? <p className="text-sm font-medium text-warning">{userListWarning}</p> : null}

            <div className="overflow-x-auto rounded-lg border border-white/5">
              <table className="w-full min-w-[520px] text-left text-xs">
                <thead className="bg-white/[0.03] text-text-tertiary">
                  <tr>
                    <th className="px-3 py-2 font-bold">Email</th>
                    <th className="px-3 py-2 font-bold">Plan</th>
                    <th className="px-3 py-2 font-bold">Expires</th>
                  </tr>
                </thead>
                <tbody>
                  {isLoading ? (
                    <tr>
                      <td colSpan={3} className="px-3 py-8 text-center text-text-secondary">
                        Loading users…
                      </td>
                    </tr>
                  ) : visibleUsers.length === 0 ? (
                    <tr>
                      <td colSpan={3} className="px-3 py-8 text-center text-text-secondary">
                        No users found.
                      </td>
                    </tr>
                  ) : (
                    visibleUsers.map((user) => {
                      const meta = getAccessMeta(user);
                      return (
                        <tr
                          key={user.id}
                          onClick={() => setSelected(user)}
                          className={cn(
                            "cursor-pointer border-t border-white/5 transition-colors hover:bg-white/[0.03]",
                            selected?.id === user.id && "bg-accent/10"
                          )}
                        >
                          <td className="px-3 py-3">
                            <div className="min-w-0">
                              <p className="truncate font-medium text-text-primary">{user.email}</p>
                              {user.adminNote ? <p className="mt-1 truncate text-[11px] text-text-tertiary">{user.adminNote}</p> : null}
                            </div>
                          </td>
                          <td className="px-3 py-3">
                            <div className="flex flex-wrap items-center gap-2">
                              <span className="capitalize text-text-secondary">{user.entitlement}</span>
                              <StatusBadge tone={meta.tone} label={meta.label} />
                            </div>
                          </td>
                          <td className="px-3 py-3 text-text-tertiary">
                            {user.entitlement === "free"
                              ? "—"
                              : user.entitlementExpiresAt
                                ? formatExpiryDate(user.entitlementExpiresAt) ?? "—"
                                : "Lifetime"}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            <div className="flex items-center justify-between gap-2">
              <button
                type="button"
                disabled={page <= 1}
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                className="rounded-full border border-white/10 px-3 py-1.5 text-xs font-bold disabled:opacity-40"
              >
                Previous
              </button>
              <p className="text-xs text-text-tertiary">
                Page {page} of {totalPages}
              </p>
              <button
                type="button"
                disabled={page >= totalPages}
                onClick={() => setPage((p) => p + 1)}
                className="rounded-full border border-white/10 px-3 py-1.5 text-xs font-bold disabled:opacity-40"
              >
                Next
              </button>
            </div>
          </section>

          <aside className="h-fit space-y-4 rounded-xl border border-white/5 bg-surface p-4 lg:sticky lg:top-6">
            {selected ? (
              <>
                <div className="space-y-3">
                  <p className="text-xs font-bold uppercase text-text-tertiary">Selected account</p>
                  <p className="break-all text-sm font-black text-white">{selected.email}</p>
                  {selected.name ? <p className="text-xs text-text-secondary">{selected.name}</p> : null}
                  <div className="grid grid-cols-2 gap-2">
                    <SelectedMetric label="Current plan" value={selected.entitlement} />
                    <SelectedMetric label="Status" value={selectedMeta?.label || "Unknown"} tone={selectedMeta?.tone} />
                    <SelectedMetric
                      label="Expires"
                      value={
                        selected.entitlement === "free"
                          ? "No access"
                          : selected.entitlementExpiresAt
                            ? formatExpiryDate(selected.entitlementExpiresAt) || "Unknown"
                            : "Lifetime"
                      }
                    />
                    <SelectedMetric label="Created" value={formatExpiryDate(selected.created) || "Unknown"} />
                  </div>
                </div>

                <label className="block space-y-2">
                  <span className="text-xs font-bold uppercase text-text-tertiary">Plan</span>
                  <select
                    value={entitlement}
                    onChange={(event) => setEntitlement(event.target.value as FottyPlan)}
                    className="w-full rounded-lg border border-white/10 bg-background px-3 py-2.5 text-sm font-medium"
                  >
                    {PLAN_OPTIONS.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </label>

                <div className="space-y-2">
                  <span className="text-xs font-bold uppercase text-text-tertiary">Quick apply</span>
                  <div className="flex flex-wrap gap-2">
                    {ACCESS_PRESETS.map((preset) => (
                      <button
                        key={preset.id}
                        type="button"
                        onClick={() => applyPreset(preset.id)}
                        className="rounded-full border border-white/10 bg-background px-3 py-1.5 text-[11px] font-bold text-text-secondary hover:border-accent/30 hover:text-white"
                      >
                        {preset.label}
                      </button>
                    ))}
                  </div>
                </div>

                <label className="block space-y-2">
                  <span className="text-xs font-bold uppercase text-text-tertiary">Expires (optional)</span>
                  <input
                    type="date"
                    value={expiresAt}
                    onChange={(event) => setExpiresAt(event.target.value)}
                    className="w-full rounded-lg border border-white/10 bg-background px-3 py-2.5 text-sm font-medium"
                  />
                  <p className="text-[11px] text-text-tertiary">
                    Clear date for lifetime Plus. Annual ≈ 1 year · Match-Day ≈ 7 days.
                  </p>
                </label>

                <label className="block space-y-2">
                  <span className="text-xs font-bold uppercase text-text-tertiary">Admin note</span>
                  <textarea
                    value={adminNote}
                    onChange={(event) => setAdminNote(event.target.value)}
                    rows={3}
                    placeholder="TT$100 May bank ref, WhatsApp 17 May…"
                    className="w-full resize-none rounded-lg border border-white/10 bg-background px-3 py-2.5 text-sm font-medium"
                  />
                </label>

                <div className="space-y-2">
                  <span className="text-xs font-bold uppercase text-text-tertiary">Note templates</span>
                  <div className="flex flex-wrap gap-2">
                    {["WhatsApp paid", "Bank transfer", "Cash", "Test access", "Comped"].map((template) => (
                      <button
                        key={template}
                        type="button"
                        onClick={() => setAdminNote((note) => (note ? `${note}; ${template}` : template))}
                        className="rounded-full border border-white/10 bg-background px-3 py-1.5 text-[11px] font-bold text-text-secondary hover:border-accent/30 hover:text-white"
                      >
                        {template}
                      </button>
                    ))}
                  </div>
                </div>

                <button
                  type="button"
                  disabled={isSaving}
                  onClick={() => void handleSave()}
                  className="inline-flex min-h-11 w-full items-center justify-center rounded-lg accent-gradient px-4 text-sm font-black text-white disabled:opacity-60"
                >
                  {isSaving ? "Saving…" : "Save access"}
                </button>

                {saveMessage ? (
                  <p className={cn("text-xs font-medium", saveMessage.startsWith("Access") ? "text-success" : "text-warning")}>
                    {saveMessage}
                  </p>
                ) : null}

                <div className="space-y-3 rounded-lg border border-accent/20 bg-accent/5 p-3">
                  <div className="flex items-start gap-3">
                    <QrCode size={18} className="mt-0.5 shrink-0 text-accent" />
                    <div className="min-w-0">
                      <p className="text-xs font-black uppercase text-white">One-time QR login</p>
                      <p className="mt-1 text-[11px] font-medium leading-5 text-text-secondary">
                        Creates a 15-minute, single-use scan link for this account. Works without sharing the password.
                      </p>
                    </div>
                  </div>
                  <button
                    type="button"
                    disabled={isGeneratingLoginLink || userSource !== "pocketbase"}
                    onClick={() => void handleGenerateLoginLink()}
                    className="inline-flex min-h-10 w-full items-center justify-center gap-2 rounded-lg border border-accent/30 bg-accent/10 px-3 text-xs font-bold text-accent disabled:opacity-50"
                  >
                    <QrCode size={14} />
                    {isGeneratingLoginLink ? "Generating..." : "Generate QR login"}
                  </button>
                  {loginLink ? (
                    <div className="space-y-3 rounded-lg border border-white/10 bg-background p-3">
                      <img
                        src={`https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=12&data=${encodeURIComponent(loginLink.url)}`}
                        alt={`QR login for ${loginLink.email}`}
                        className="mx-auto h-44 w-44 rounded-lg bg-white p-2"
                      />
                      <p className="break-all text-[11px] font-medium text-text-secondary">{loginLink.url}</p>
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <p className="text-[11px] font-bold text-text-tertiary">
                          Expires {formatExpiryDate(loginLink.expiresAt) || "soon"}
                        </p>
                        <button
                          type="button"
                          onClick={() => void copyLoginLink()}
                          className="inline-flex min-h-9 items-center gap-2 rounded-full border border-white/10 px-3 text-[11px] font-bold text-white"
                        >
                          {loginLinkCopied ? <Check size={13} /> : <Copy size={13} />}
                          {loginLinkCopied ? "Copied" : "Copy link"}
                        </button>
                      </div>
                    </div>
                  ) : null}
                </div>

                {whatsappHref ? (
                  <a
                    href={whatsappHref}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex min-h-10 w-full items-center justify-center rounded-lg border border-[#25D366]/30 bg-[#25D366]/10 px-3 text-xs font-bold text-[#25D366]"
                  >
                    Open WhatsApp thread
                  </a>
                ) : null}

                <div className="space-y-3 border-t border-danger/20 pt-4">
                  <p className="text-xs font-bold uppercase text-danger">Danger zone</p>
                  {!showDeleteConfirm ? (
                    <button
                      type="button"
                      onClick={() => setShowDeleteConfirm(true)}
                      className="inline-flex min-h-10 w-full items-center justify-center gap-2 rounded-lg border border-danger/30 bg-danger/10 px-3 text-xs font-bold text-danger"
                    >
                      <AlertTriangle size={14} />
                      Delete account
                    </button>
                  ) : (
                    <div className="space-y-3 rounded-lg border border-danger/30 bg-danger/5 p-3">
                      <p className="text-[11px] font-medium leading-5 text-text-secondary">
                        Permanently removes this login
                        {userSource === "pocketbase" ? " from PocketBase" : " from local grants"}. Cannot be undone.
                      </p>
                      <label className="block space-y-1">
                        <span className="text-[11px] font-bold text-text-tertiary">Type email to confirm</span>
                        <input
                          value={deleteConfirmEmail}
                          onChange={(event) => setDeleteConfirmEmail(event.target.value)}
                          placeholder={selected.email}
                          className="w-full rounded-lg border border-white/10 bg-background px-3 py-2 text-sm font-medium"
                          autoComplete="off"
                        />
                      </label>
                      <div className="flex flex-wrap gap-2">
                        <button
                          type="button"
                          disabled={
                            isDeleting ||
                            deleteConfirmEmail.trim().toLowerCase() !== selected.email.trim().toLowerCase()
                          }
                          onClick={() => void handleDelete()}
                          className="rounded-lg bg-danger px-3 py-2 text-xs font-bold text-white disabled:opacity-50"
                        >
                          {isDeleting ? "Deleting…" : "Delete permanently"}
                        </button>
                        <button
                          type="button"
                          disabled={isDeleting}
                          onClick={() => {
                            setShowDeleteConfirm(false);
                            setDeleteConfirmEmail("");
                          }}
                          className="rounded-lg border border-white/10 px-3 py-2 text-xs font-bold text-text-secondary"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              </>
            ) : (
              <div className="py-8 text-center text-sm text-text-secondary">
                <Shield size={28} className="mx-auto mb-3 text-text-tertiary" />
                Select a user to edit access.
              </div>
            )}
          </aside>
        </div>

        <p className="text-xs text-text-tertiary">
          Requires <code className="text-accent">POCKETBASE_ADMIN_TOKEN</code> on the server. Optional PocketBase user fields:{" "}
          <code className="text-accent">entitlementExpiresAt</code>, <code className="text-accent">adminNote</code> (text).{" "}
          <Link href="/subscribe" className="font-bold text-accent hover:underline">
            View public plans
          </Link>
        </p>
      </main>
    </AdminPageShell>
  );
}

function SummaryCard({
  icon: Icon,
  label,
  value,
  tone = "neutral",
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  tone?: "neutral" | "active" | "expiring" | "expired" | "lifetime";
}) {
  return (
    <div className="rounded-xl border border-white/5 bg-surface p-4">
      <div className="flex items-center justify-between gap-3">
        <p className="text-[11px] font-black uppercase tracking-wide text-text-tertiary">{label}</p>
        <Icon
          size={16}
          className={cn(
            tone === "active" && "text-success",
            tone === "expiring" && "text-live",
            tone === "expired" && "text-danger",
            tone === "lifetime" && "text-accent",
            tone === "neutral" && "text-text-tertiary"
          )}
        />
      </div>
      <p className="mt-3 text-2xl font-black text-white">{value}</p>
    </div>
  );
}

function StatusBadge({ tone, label }: { tone: string; label: string }) {
  return (
    <span
      className={cn(
        "rounded-full border px-2 py-0.5 text-[10px] font-black uppercase",
        tone === "active" && "border-success/25 bg-success/10 text-success",
        tone === "expiring" && "border-live/25 bg-live/10 text-live",
        tone === "expired" && "border-danger/25 bg-danger/10 text-danger",
        tone === "lifetime" && "border-accent/25 bg-accent/10 text-accent",
        tone === "neutral" && "border-white/10 bg-white/5 text-text-tertiary"
      )}
    >
      {label}
    </span>
  );
}

function SelectedMetric({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-lg border border-white/5 bg-background p-3">
      <p className="text-[10px] font-black uppercase tracking-wide text-text-tertiary">{label}</p>
      <p
        className={cn(
          "mt-1 truncate text-sm font-black capitalize text-text-primary",
          tone === "active" && "text-success",
          tone === "expiring" && "text-live",
          tone === "expired" && "text-danger",
          tone === "lifetime" && "text-accent"
        )}
      >
        {value}
      </p>
    </div>
  );
}
