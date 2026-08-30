"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, CheckCircle2, Copy } from "lucide-react";

interface AdminStatus {
  adminPasswordConfigured: boolean;
  pocketbaseTokenConfigured: boolean;
  pocketbaseReachable: boolean;
  pocketbaseUrl: string;
  optionalFieldsReady: boolean | null;
  missingFields: string[];
  usingLocalGrants?: boolean;
  ready: boolean;
}

const PB_FIELD_STEPS = [
  "Open PocketBase admin → Collections → users",
  'Add text field "entitlement" (if missing)',
  'Add text field "plan" (optional mirror)',
  'Add text field "entitlementExpiresAt" (ISO date for expiry)',
  'Add text field "adminNote" (payment / WhatsApp notes)',
];

export function AdminSetupBanner() {
  const [status, setStatus] = useState<AdminStatus | null>(null);
  const [copied, setCopied] = useState(false);

  const loadStatus = () => {
    fetch("/api/admin/status", { cache: "no-store" })
      .then((res) => res.json())
      .then((data) => setStatus(data as AdminStatus))
      .catch(() => setStatus(null));
  };

  useEffect(() => {
    loadStatus();
    const onRefresh = () => loadStatus();
    window.addEventListener("fotty:admin-status-refresh", onRefresh);
    return () => window.removeEventListener("fotty:admin-status-refresh", onRefresh);
  }, []);

  if (!status || status.ready) return null;

  const setupCommand =
    "cd web && POCKETBASE_ADMIN_TOKEN=paste_from_pb_settings npm run pb:admin-setup";
  const setupCommandAlt =
    "cd web && PB_ADMIN_EMAIL=your@email PB_ADMIN_PASSWORD=your-password npm run pb:admin-setup";

  async function copyCommand() {
    try {
      await navigator.clipboard.writeText(setupCommand);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // ignore
    }
  }

  return (
    <section className="rounded-xl border border-warning/30 bg-warning/10 p-4">
      <div className="flex gap-3">
        <AlertTriangle size={20} className="mt-0.5 shrink-0 text-warning" />
        <div className="min-w-0 flex-1 space-y-3">
          <div>
            <p className="text-sm font-black text-white">Finish server setup</p>
            <p className="mt-1 text-xs font-medium leading-5 text-text-secondary">
              The dashboard UI is ready. Complete these once in <code className="text-accent">web/.env.local</code> and PocketBase.
            </p>
          </div>

          <ul className="space-y-2 text-xs font-medium text-text-secondary">
            <li className="flex items-start gap-2">
              {status.adminPasswordConfigured ? (
                <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-success" />
              ) : (
                <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-warning" />
              )}
              <span>
                <strong className="text-text-primary">FOTTY_ADMIN_PASSWORD</strong> — set in .env.local (you use this to sign in here)
              </span>
            </li>
            <li className="flex items-start gap-2">
              {status.pocketbaseTokenConfigured && status.pocketbaseReachable ? (
                <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-success" />
              ) : (
                <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-warning" />
              )}
              <span>
                <strong className="text-text-primary">POCKETBASE_ADMIN_TOKEN</strong> — from PocketBase → Settings → API keys, or run setup script below
                {!status.pocketbaseReachable && status.pocketbaseTokenConfigured ? (
                  <span className="block text-error">Token set but PocketBase unreachable at {status.pocketbaseUrl}</span>
                ) : null}
              </span>
            </li>
            <li className="flex items-start gap-2">
              {status.optionalFieldsReady ? (
                <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-success" />
              ) : (
                <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-warning" />
              )}
              <span>
                <strong className="text-text-primary">users collection fields</strong>
                {status.missingFields?.length ? (
                  <span className="block">Missing: {status.missingFields.join(", ")}</span>
                ) : (
                  <span className="block">Add entitlement + expiry + note fields (see steps)</span>
                )}
              </span>
            </li>
          </ul>

          {status.optionalFieldsReady === false ? (
            <ol className="list-decimal space-y-1 pl-4 text-[11px] leading-5 text-text-tertiary">
              {PB_FIELD_STEPS.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          ) : null}

          <div className="rounded-lg border border-white/10 bg-background/80 p-3">
            <p className="text-[11px] font-bold uppercase text-text-tertiary">Auto-setup (recommended)</p>
            <code className="mt-2 block break-all text-[11px] text-text-secondary">{setupCommand}</code>
            <p className="mt-2 text-[10px] text-text-tertiary">Or superuser login:</p>
            <code className="mt-1 block break-all text-[11px] text-text-secondary">{setupCommandAlt}</code>
            <button
              type="button"
              onClick={() => void copyCommand()}
              className="mt-2 inline-flex items-center gap-1.5 text-[11px] font-bold text-accent"
            >
              <Copy size={12} />
              {copied ? "Copied" : "Copy command"}
            </button>
          </div>

          <p className="text-[11px] text-text-tertiary">Restart <code>npm run dev</code> after updating .env.local.</p>
        </div>
      </div>
    </section>
  );
}
