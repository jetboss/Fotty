import MediaDetailPage from "./MediaPageClient";

export const dynamicParams = false;

export function generateStaticParams() {
  return [{ type: "movie", id: "index" }];
}

export default function Page() {
  return <MediaDetailPage />;
}
