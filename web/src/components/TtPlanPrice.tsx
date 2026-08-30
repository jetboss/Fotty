import type { TtPlanDefinition } from "@/lib/tt-plans";
import { cn } from "@/lib/utils";

export function TtPlanPrice({
  plan,
  className,
  size = "md",
  align = "end",
}: {
  plan: Pick<TtPlanDefinition, "priceLabel" | "priceMessage" | "compareAtPriceLabel" | "promoBadge">;
  className?: string;
  size?: "sm" | "md";
  align?: "start" | "end";
}) {
  if (plan.priceMessage) {
    return (
      <p
        className={cn(
          "max-w-[11rem] text-right text-xs font-bold leading-4 text-text-secondary",
          align === "start" && "text-left",
          className
        )}
      >
        {plan.priceMessage}
      </p>
    );
  }

  const promo = Boolean(plan.compareAtPriceLabel);

  if (!promo) {
    return (
      <p className={cn("font-black text-accent", size === "sm" ? "text-sm" : "text-sm", className)}>
        {plan.priceLabel}
      </p>
    );
  }

  return (
    <div
      className={cn(
        "flex flex-col gap-1",
        align === "start" ? "items-start" : "items-end",
        className
      )}
    >
      <p
        className={cn(
          "font-medium text-text-tertiary line-through",
          size === "sm" ? "text-[11px]" : "text-xs"
        )}
      >
        {plan.compareAtPriceLabel}
      </p>
      <div
        className={cn(
          "flex flex-wrap gap-2",
          align === "start" ? "items-center justify-start" : "items-center justify-end"
        )}
      >
        <p className={cn("font-black text-accent", size === "sm" ? "text-sm" : "text-sm")}>{plan.priceLabel}</p>
        {plan.promoBadge ? (
          <span className="rounded-full bg-accent/15 px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide text-accent">
            {plan.promoBadge}
          </span>
        ) : null}
      </div>
    </div>
  );
}
