"""Compare a saved date-specific Sky UK schedule with Fotty's official fixture export."""
import argparse
import json
import re
from datetime import datetime, timezone, timedelta
from html.parser import HTMLParser
from pathlib import Path
from zoneinfo import ZoneInfo


class Schedule(HTMLParser):
    def __init__(self):
        super().__init__()
        self.groups = []
        self.row = None
        self.tag = None
        self.text = []
        self.heading = ''

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = attrs.get('class', '').split()
        if tag == 'div' and 'event-group' in classes:
            self.row = {'teams': []} if '-layout1' in classes and self.heading == 'Football' else None
        if tag == 'h3' or self.row is not None and (tag == 'strong' or tag == 'li' and 'col2' in classes or tag == 'p' and 'event-detail' in classes):
            self.tag = tag
            self.text = []

    def handle_data(self, data):
        if self.tag:
            self.text.append(data)

    def handle_endtag(self, tag):
        if self.tag != tag:
            return
        value = ' '.join(''.join(self.text).split())
        self.tag = None
        if tag == 'h3':
            self.heading = value
        elif tag == 'strong':
            self.row['teams'].append(value)
        elif tag == 'li':
            self.row['kickoff'] = value
        elif tag == 'p':
            self.row['listing'] = value
            self.groups.append(self.row)
            self.row = None


def clock(day, value):
    wall = datetime.strptime(value, '%H:%M').time()
    local = datetime.combine(day, wall, ZoneInfo('Europe/London'))
    utc = local.astimezone(timezone.utc)
    if local.utcoffset() != local.replace(fold=1).utcoffset() or utc.astimezone(local.tzinfo) != local:
        raise ValueError('Ambiguous local time')
    return utc


def team(name):
    return re.sub(r' (?:AFC|FC)$', '', name).casefold()


def compare(html, day, fixtures):
    cursor = (day + timedelta(days=1)).strftime('%Y%m%d')
    ordinal = 'th' if 11 <= day.day <= 13 else {1:'st', 2:'nd', 3:'rd'}.get(day.day % 10, 'th')
    heading = day.strftime('%a ') + str(day.day) + ordinal + day.strftime(' %B')
    if (html.count('data-current-page="') != 1 or f'data-current-page="{cursor}"' not in html
            or f'<h3 class="text-h4 -rs-style20">{heading}</h3>' not in html):
        raise ValueError('Unverified Sky listing date')
    parser = Schedule()
    parser.feed(html)
    results = []
    for row in parser.groups:
        fields = row['listing'].split(', ')
        if fields[0] != 'Premier League' or len(row['teams']) != 2 or 'kickoff' not in row:
            continue
        kickoff = clock(day, row['kickoff'])
        matches = []
        for fixture in fixtures:
            sides = fixture.get('participants', [])
            if (fixture.get('competitionId') != 'premier-league' or fixture.get('sport') != 'football'
                    or fixture.get('eventKind') != 'match' or fixture.get('status') not in ('scheduled', 'live')
                    or len(sides) != 2 or fixture.get('squad', {}).get('gender') != 'men'
                    or fixture['squad'].get('ageGroup') != 'senior'):
                continue
            if ({p['role']:team(p['name']) for p in sides} == dict(zip(('home','away'), map(team, row['teams'])))
                    and datetime.fromisoformat(fixture['start'].replace('Z','+00:00')) == kickoff):
                matches.append(fixture['id'])
        if len(matches) != 1:
            continue
        for field in fields[1:]:
            channel = re.fullmatch(r'(Sky Sports Main Event|Sky Sports Football|Sky Sports Premier League) \((\d\d:\d\d)\)', field)
            if channel:
                start = clock(day, channel[2])
                if timedelta(0) <= kickoff - start <= timedelta(minutes=60):
                    results.append(dict(fixture=matches[0], teams=row['teams'], station=channel[1], coverage=start.isoformat(), kickoff=kickoff.isoformat()))
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('sky', 'fixtures', 'date'):
        parser.add_argument(name)
    args = parser.parse_args()
    print(json.dumps(compare(Path(args.sky).read_text(), datetime.strptime(args.date,'%Y-%m-%d').date(),
                             json.loads(Path(args.fixtures).read_text())['fixtures']), indent=2))
