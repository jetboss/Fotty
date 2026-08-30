import Link from "next/link";

export function LegalFooter() {
  return (
    <footer className="px-md pb-6 pt-2 text-center">
      <p className="text-[11px] font-medium leading-5 text-text-tertiary">
        <Link href="/privacy" className="text-text-secondary hover:text-text-primary">
          Privacy
        </Link>
        <span className="px-2 text-white/20">·</span>
        <Link href="/terms" className="text-text-secondary hover:text-text-primary">
          Terms
        </Link>
        <span className="px-2 text-white/20">·</span>
        <Link href="/help" className="text-text-secondary hover:text-text-primary">
          Help
        </Link>
      </p>
    </footer>
  );
}
