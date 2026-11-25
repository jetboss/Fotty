/** User-facing stream labels (never show upstream provider names in the UI). */

export function fottyFeedLabel(index: number) {
  return `Fotty ${index + 1}`;
}

export function fottyFeedCountLabel(count: number) {
  return count === 1 ? "1 feed" : `${count} feeds`;
}

export function fottyFeedCountShort(count: number): string | null {
  if (count <= 0) return null;
  return count === 1 ? "1 Fotty feed" : `${count} Fotty feeds`;
}
