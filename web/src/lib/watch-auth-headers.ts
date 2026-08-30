/** Account-backed watch routes are retired; supported playback uses no user credentials. */
export function getWatchAuthHeaders(): Record<string, string> {
  return {};
}
