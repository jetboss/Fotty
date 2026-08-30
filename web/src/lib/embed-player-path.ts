export function fottyEmbedPlayerProxyPath(
  source: string,
  id: string,
  streamNo: number,
  watchToken?: string
) {
  const params = new URLSearchParams({
    source,
    id,
    streamNo: String(streamNo),
  });
  if (watchToken) params.set("watchToken", watchToken);
  return `/api/embed/player?${params.toString()}`;
}
