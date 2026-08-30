from typing import Dict, List, Optional
from urllib.parse import urljoin


def classify_manifest_failure(status_code: int = 0, timed_out: bool = False) -> str:
    if timed_out:
        return "timeout"
    if status_code == 524:
        return "524"
    if status_code > 0:
        return f"manifest_{status_code}"
    return "manifest_error"


def classify_segment_failure(status_code: int, bytes_read: int, minimum_segment_bytes: int = 512) -> str:
    if status_code < 200 or status_code > 299:
        return f"segment_{status_code}"
    if bytes_read < minimum_segment_bytes:
        return "segment_small"
    return "ok"


def parse_manifest_lines(manifest_text: str) -> List[str]:
    return manifest_text.replace("\r\n", "\n").split("\n")


def is_segment_line(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and not stripped.startswith("#")


def extract_media_sequence(manifest_text: Optional[str]) -> Optional[int]:
    if not manifest_text:
        return None
    for line in parse_manifest_lines(manifest_text):
        if line.startswith("#EXT-X-MEDIA-SEQUENCE:"):
            try:
                return int(line.split(":")[1].strip())
            except (IndexError, ValueError):
                return None
    return None


def absolute_url(line: str, manifest_url: str) -> str:
    stripped = line.strip()
    if stripped.startswith("//"):
        return "https:" + stripped
    return urljoin(manifest_url, stripped)


def rewrite_manifest(
    original_manifest: str,
    manifest_url: str,
    valid_segment_urls: Dict[str, str],
) -> str:
    lines = parse_manifest_lines(original_manifest)
    output: List[str] = []
    pending_extinf: str | None = None

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue

        if line.startswith("#EXTINF"):
            pending_extinf = raw_line
            continue

        if is_segment_line(line):
            resolved = absolute_url(line, manifest_url)
            replacement = valid_segment_urls.get(resolved)
            if replacement:
                if pending_extinf is not None:
                    output.append(pending_extinf)
                output.append(replacement)
            pending_extinf = None
            continue

        pending_extinf = None
        output.append(raw_line)

    return "\n".join(output) + "\n"
