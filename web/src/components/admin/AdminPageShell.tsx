import { cn } from "@/lib/utils";

/** Full-viewport admin shell (no main app nav). */
export function AdminPageShell({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <div className={cn("min-h-dvh w-full bg-background text-text-primary", className)}>{children}</div>;
}
