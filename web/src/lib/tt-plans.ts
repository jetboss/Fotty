import type { FottyPlan } from "@/lib/entitlements";
import type { PaidPlan } from "@/lib/billing-plans";

/** Paid plans available for Trinidad & Tobago — WhatsApp + bank transfer activation. */
export type TtCheckoutPlanId =
  | "supporter"
  | "plus_annual"
  | "plus_lifetime"
  | "plus"
  | "builder"
  | "collab";

export interface TtPlanDefinition {
  id: TtCheckoutPlanId;
  entitlement: FottyPlan;
  title: string;
  /** Current price customers pay (promo when compareAtPriceLabel is set). */
  priceLabel: string;
  /** When set, shown instead of priceLabel (e.g. lifetime — quote on WhatsApp). */
  priceMessage?: string;
  /** Full price shown struck through during a limited-time promo. */
  compareAtPriceLabel?: string;
  /** Short badge, e.g. "Limited-time discount". */
  promoBadge?: string;
  billingNote: string;
  description: string;
  supportMessage: string;
  features: string[];
  highlight?: boolean;
  /** Shown after Builder / Collab on subscribe — not in the main ladder. */
  secondary?: boolean;
}

export const TT_PLANS: TtPlanDefinition[] = [
  {
    id: "supporter",
    entitlement: "supporter",
    title: "Match-Day Pass",
    priceLabel: "TT$25 once",
    billingNote: "7 days of Plus access after payment is confirmed.",
    description: "Keep one big fixture or weekend organized with Plus match-day tools.",
    supportMessage: "Helps cover data, hosting, and reliability work for that match window.",
    features: [
      "Plus match-day tools for 7 days",
      "Live Board source organization",
      "Tracked teams and reminders",
      "Activated via WhatsApp after payment",
    ],
  },
  {
    id: "plus_annual",
    entitlement: "plus",
    title: "Fotty Plus · Annual",
    priceLabel: "TT$700 / year",
    compareAtPriceLabel: "TT$780 / year",
    promoBadge: "2 months free vs monthly",
    billingNote: "One payment per year — same Plus access, renewed after 12 months.",
    description: "Best value for regular fans who want one payment and a full season of match-day organization.",
    supportMessage: "Supports hosting, football data, and steady improvements all year.",
    highlight: true,
    features: [
      "Full Plus match-day tools for 12 months",
      "Live Board organization, guide context, and reminders",
      "Cloud-synced teams across devices",
      "One WhatsApp payment — no monthly renewals",
    ],
  },
  {
    id: "plus",
    entitlement: "plus",
    title: "Fotty Plus · Monthly",
    priceLabel: "TT$65 / month",
    compareAtPriceLabel: "TT$100 / month",
    promoBadge: "Limited-time discount",
    billingNote:
      "Renews monthly at the launch price while the promo runs — message us each month or set up a standing order in chat.",
    description: "Plus match-day tools month to month — flexible if you prefer paying as you go.",
    supportMessage: "Supports hosting, football data, and steady improvements.",
    features: [
      "Everything in Match-Day Pass, ongoing",
      "Cloud-synced teams and reminders",
      "Priority source organization on the board",
      "Direct WhatsApp support",
    ],
  },
  {
    id: "plus_lifetime",
    entitlement: "plus",
    title: "Fotty Plus · Lifetime",
    priceLabel: "",
    priceMessage: "Message us for lifetime pricing",
    billingNote: "One payment — Plus access with no expiry. We'll confirm your quote in WhatsApp.",
    description: "For supporters who want Fotty long-term without renewals. Tap WhatsApp to get the current lifetime rate.",
    supportMessage: "Helps fund the product as an independent Trinidad & Tobago build.",
    features: [
      "Full Plus match-day tools — lifetime on your account",
      "All future Plus features included",
      "Priority support in WhatsApp",
      "One-time payment — no renewals",
    ],
  },
  {
    id: "builder",
    entitlement: "builder",
    title: "Fotty Builder",
    priceLabel: "TT$100 / month",
    compareAtPriceLabel: "TT$150 / month",
    promoBadge: "Limited-time launch price",
    billingNote: "Same Plus tools — funds reliability and product work first. Ask on WhatsApp.",
    description: "For supporters who want Fotty to grow faster in Trinidad & Tobago.",
    supportMessage: "Funds servers, APIs, new features, and TT-focused polish.",
    secondary: true,
    features: [
      "Full Plus match-day tools",
      "Funds new features and reliability work",
      "Priority feedback on what we build next",
      "Helping an independent T&T product survive",
    ],
  },
  {
    id: "collab",
    entitlement: "collab",
    title: "Fotty Collab",
    priceLabel: "Custom (TTD)",
    billingNote: "Venues, fan clubs, sponsors — we'll quote in WhatsApp.",
    description: "Watch parties, community hubs, and match-day placements for groups.",
    supportMessage: "Partnership pricing depends on your event and audience.",
    secondary: true,
    features: [
      "Watch party kit",
      "Community or sponsor placement",
      "Custom match-day workflow",
      "Quote and invoice in chat",
    ],
  },
];

/** Primary ladder on /subscribe — match-day, annual, monthly, lifetime last. */
export const TT_PLANS_PRIMARY = TT_PLANS.filter((plan) => !plan.secondary);

/** Builder, Collab, and other secondary offers. */
export const TT_PLANS_SECONDARY = TT_PLANS.filter((plan) => plan.secondary);

export function getTtPlan(id: TtCheckoutPlanId) {
  return TT_PLANS.find((plan) => plan.id === id) ?? TT_PLANS.find((plan) => plan.id === "plus_annual")!;
}

export function checkoutPlanToEntitlement(id: TtCheckoutPlanId): PaidPlan {
  return getTtPlan(id).entitlement as PaidPlan;
}

/** Price line for WhatsApp checkout and receipts. */
export function formatPlanCheckoutPrice(plan: TtPlanDefinition) {
  if (plan.priceMessage) return plan.priceMessage;
  if (plan.compareAtPriceLabel) {
    return `${plan.priceLabel} (limited-time promo — regular ${plan.compareAtPriceLabel})`;
  }
  return plan.priceLabel;
}

/** E.164 digits only for wa.me (e.g. 18681234567). */
export function getWhatsAppNumberDigits(): string | null {
  const raw = process.env.NEXT_PUBLIC_FOTTY_WHATSAPP_NUMBER?.replace(/\D/g, "") ?? "";
  if (!raw) return null;
  if (raw.length === 10 && raw.startsWith("868")) return `1${raw}`;
  if (raw.length === 7) return `1868${raw}`;
  if (raw.length >= 11) return raw;
  return raw;
}

export function isWhatsAppConfigured() {
  return Boolean(getWhatsAppNumberDigits());
}

export function buildWhatsAppPayUrl(
  planId: TtCheckoutPlanId,
  options?: { email?: string; displayName?: string }
) {
  const digits = getWhatsAppNumberDigits();
  if (!digits) return null;

  const plan = getTtPlan(planId);
  const emailLine = options?.email?.trim()
    ? options.email.trim()
    : "(I'll create or sign in to my Fotty account)";

  const priceLine = plan.priceMessage
    ? `I'm interested in ${plan.title}. Please send lifetime pricing and bank transfer details.`
    : `I'm in Trinidad & Tobago and want ${plan.title} (${formatPlanCheckoutPrice(plan)}).`;

  const lines = [
    `Hi Fotty — ${priceLine}`,
    "",
    `Fotty account email: ${emailLine}`,
    options?.displayName?.trim() ? `Name: ${options.displayName.trim()}` : null,
    "",
    "Please send bank transfer details. I'll reply with payment proof when done.",
    "",
    "Thanks for building Fotty for T&T!",
  ].filter((line): line is string => Boolean(line));

  return `https://wa.me/${digits}?text=${encodeURIComponent(lines.join("\n"))}`;
}

export function formatTtd(amount: number) {
  return `TT$${amount.toLocaleString("en-TT")}`;
}
