#!/usr/bin/env python3
"""Compare ESPN's named Caribbean editions with official fixtures and Fotty registry links."""
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from zoneinfo import ZoneInfo

FEED = "https://caribbean.espnpressroom.com/category/english-premier-league/feed/"
API = "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api"
EDITIONS = {"ESPN", "ESPN2", "ESPN Extra", "ESPN on Disney+"}
UTC = timezone.utc


class Paragraphs(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows = []
        self.text = None

    def handle_starttag(self, tag, attrs):
        if tag == "p":
            self.text = ""
        elif tag == "br" and self.text is not None:
            self.text += "\n"

    def handle_data(self, data):
        if self.text is not None:
            self.text += data

    def handle_endtag(self, tag):
        if tag == "p" and self.text is not None:
            self.rows.extend(" ".join(line.split()) for line in self.text.splitlines() if line.strip())
            self.text = None


def schedule(xml, now):
    if len(xml) > 1_048_576 or b"<!DOCTYPE" in xml.upper():
        raise ValueError("Invalid feed")
    channel = ET.fromstring(xml).find("channel")
    if channel is None or channel.findtext("link") != FEED.removesuffix("feed/"):
        raise ValueError("Unexpected publisher")
    listings = set()
    for item in channel.findall("item")[:20]:
        link = item.findtext("link", "")
        if not re.fullmatch(r"https://caribbean\.espnpressroom\.com/press-releases/20\d\d/\d\d/[a-z0-9-]+/", link):
            continue
        parser = Paragraphs()
        parser.feed(item.findtext("{http://purl.org/rss/1.0/modules/content/}encoded", ""))
        section = False
        day = None
        for line in parser.rows:
            if re.fullmatch(r"ESPN[’']s Schedule for this Weekend[’']s Coverage of the 20\d\d-\d\d Premier League Season \(ET\)", line, re.I):
                section, day = True, None
                continue
            if not section:
                continue
            if re.fullmatch(r"[A-Z][a-z]{2} \d{1,2}/\d{1,2}/20\d{2}", line):
                day = datetime.strptime(line[4:], "%m/%d/%Y")
                if day.strftime("%a") != line[:3]:
                    day = None
                continue
            row = re.fullmatch(r"(\d{1,2}(?::\d{2})? [AP]M) (.+?) vs\. (.+?), (.+)", line)
            if not row:
                section = False
                continue
            if day is None:
                continue
            at, home, away, platforms = row.groups()
            clock = datetime.strptime(at, "%I:%M %p" if ":" in at else "%I %p").time()
            local = datetime.combine(day.date(), clock, ZoneInfo("America/New_York"))
            start = local.astimezone(UTC)
            if local.utcoffset() != local.replace(fold=1).utcoffset() or start.astimezone(local.tzinfo) != local:
                continue
            stations = platforms.split(", ")
            if set(stations) <= EDITIONS and abs(start-now) <= timedelta(days=8):
                listings.add((start, home, away, tuple(stations)))
    editions = {}
    for start, home, away, stations in listings:
        editions.setdefault((start, home, away), set()).add(tuple(sorted(stations)))
    return sorted((*key, next(iter(options))) for key, options in editions.items() if len(options) == 1)


def instant(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def club(name):
    return re.sub(r" (?:AFC|FC)$", "", name, flags=re.I).casefold()


def match(listing, fixtures):
    start, home, away, _ = listing
    found = []
    for row in fixtures:
        if (row.get("competitionId"), row.get("sport"), row.get("eventKind")) != ("premier-league", "football", "match"):
            continue
        if row.get("squad", {}).get("gender") != "men" or row["squad"].get("ageGroup") != "senior":
            continue
        sides = {p["role"]: club(p["name"]) for p in row["participants"]}
        if len(row["participants"]) == 2 and sides == {"home": club(home), "away": club(away)} and instant(row["start"]) == start:
            found.append(row)
    return found[0] if len(found) == 1 else None


def fetch(url, headers=()):
    args = ["curl", "--fail", "--silent", "--show-error", "--max-time", "12", "--max-filesize", "2097152"]
    for header in headers:
        args += ["-H", header]
    return subprocess.check_output(args + [url])


def main():
    now = datetime.now(UTC)
    listings = schedule(fetch(FEED), now)
    fixtures = json.loads(fetch(API + "/sports/fixtures"))
    registry = json.loads(fetch(API + "/live/broadcasts", ["X-Fotty-Broadcast-Capabilities: reviewedtv-programme-v1",
        "X-Fotty-Broadcast-Assignments: reviewedtv-programme-v2", "X-Fotty-TV-Guide: reviewedtv-guide-v1"]))
    result = []
    for listing in listings:
        row = match(listing, fixtures["fixtures"])
        if row is None:
            continue
        start, home, away, stations = listing
        evidence = {b["id"]: b for b in registry["broadcasts"] if instant(b["expiresAt"]) > now}
        links = set()
        if row["status"] in {"live", "scheduled"}:
            for link in registry["links"]:
                broadcast = evidence.get(link["broadcastID"])
                if (link["fixtureID"] == row["id"] and instant(link["expiresAt"]) > now
                        and broadcast and link["providerCode"] == broadcast["providerCode"]):
                    links.add(link["providerCode"])
        result.append(dict(match=f"{home} vs {away}", kickoff=start.isoformat(), status=row["status"],
                           publishedPlatforms=stations, currentRegistryProviders=sorted(links)))
    print(json.dumps(dict(observedAt=now.isoformat(), publisherListingsInWindow=len(listings),
                          exactOfficialMatches=result), indent=2))


if __name__ == "__main__":
    main()
