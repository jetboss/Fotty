"use client";

import { useEffect } from "react";
import { RouteErrorView } from "@/components/RouteStates";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return <RouteErrorView title="League tables failed to load" reset={reset} />;
}
