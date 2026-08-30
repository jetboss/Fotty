"use client";

import React from "react";
import Link from "next/link";
import { trackEvent } from "@/lib/analytics";

interface FottyErrorBoundaryProps {
  children: React.ReactNode;
}

interface FottyErrorBoundaryState {
  hasError: boolean;
  message: string;
}

export class FottyErrorBoundary extends React.Component<FottyErrorBoundaryProps, FottyErrorBoundaryState> {
  constructor(props: FottyErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, message: "" };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, message: error.message || "Something went wrong." };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    trackEvent("runtime_error", {
      message: error.message.slice(0, 200),
      componentStack: info.componentStack?.slice(0, 200),
    });
  }

  render() {
    if (!this.state.hasError) {
      return this.props.children;
    }

    return (
      <main className="flex min-h-[50vh] flex-col items-center justify-center gap-4 px-6 py-16 text-center">
        <h1 className="text-xl font-black text-white">Fotty hit a snag</h1>
        <p className="max-w-md text-sm font-medium text-text-secondary">
          This page failed to load. Try again or head back to the live board.
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          <button
            type="button"
            onClick={() => this.setState({ hasError: false, message: "" })}
            className="rounded-full bg-white/10 px-4 py-2 text-xs font-bold text-white"
          >
            Try again
          </button>
          <Link href="/" className="rounded-full accent-gradient px-4 py-2 text-xs font-bold text-white">
            Live board
          </Link>
        </div>
      </main>
    );
  }
}
