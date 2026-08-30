import WatchPageClient from "./WatchPageClient";

/** All watch links use `/watch/index`; the real content id stays in query params. */
export const dynamicParams = false;

export function generateStaticParams() {
  return [{ id: "index" }];
}

export default function Page() {
  return <WatchPageClient />;
}
