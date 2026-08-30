"use client";

import { MessageCircle } from "lucide-react";
import type { TtCheckoutPlanId } from "@/lib/tt-plans";
import { buildWhatsAppPayUrl, isWhatsAppConfigured } from "@/lib/tt-plans";
import { trackEvent } from "@/lib/analytics";
import { cn } from "@/lib/utils";

interface WhatsAppPayButtonProps {
  planId: TtCheckoutPlanId;
  email?: string;
  displayName?: string;
  className?: string;
  label?: string;
}

export function WhatsAppPayButton({
  planId,
  email,
  displayName,
  className,
  label = "Pay & activate on WhatsApp",
}: WhatsAppPayButtonProps) {
  const href = buildWhatsAppPayUrl(planId, { email, displayName });

  if (!isWhatsAppConfigured() || !href) {
    return (
      <p className="rounded-lg border border-white/10 bg-background/70 p-3 text-xs font-medium leading-5 text-text-secondary">
        WhatsApp payments are not configured yet. Set <code className="text-accent">NEXT_PUBLIC_FOTTY_WHATSAPP_NUMBER</code>{" "}
        (e.g. 18681234567).
      </p>
    );
  }

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      onClick={() => trackEvent("whatsapp_pay_click", { plan: planId, signedIn: Boolean(email) })}
      className={cn(
        "inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-lg bg-[#25D366] px-4 text-sm font-black text-white transition-opacity hover:opacity-95",
        className
      )}
    >
      <MessageCircle size={18} />
      {label}
    </a>
  );
}
