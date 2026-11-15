# Licensed and free official sources for Fotty

Research, 9 Nov 2026. The question: where Fotty could get legal live sports, now that Streamed/StreamEx has closed.

## The short answer

No legal free source carries full Premier League, Champions League, NFL, NBA or NHL schedules. Those are sold to paid broadcasters, for example Peacock, Paramount+, ESPN, DAZN, TNT Sports and Sky. Legal free live sport exists, but it is selected matches, smaller competitions, and 24/7 channels of replays, highlights and studio shows.

A licensed Fotty therefore looks like a guide that plays what is free and points to where everything else is legally on. It does not look like the same catalogue from new hosts.

## What Fotty uses today

`ReviewedTVPlaylistClient` reads public GitHub IPTV playlists (`iptv-org/iptv` and `doms9/iptv`). They mix two kinds of channel:

- **Free channels, published free by the rights holder.** These include FIFA+ (TV21, TV22), NBC Sports NOW (TV9) and likely beIN Sports XTRA (TV17) and Cricket Gold (TV23).
- **Paid subscription channels.** These are Sky Sports Cricket and Football (TV10, TV11), TNT Sports 1 to 3 (TV12 to TV14), USA Network (TV15), Fox Sports 1 (TV24), and Willow through a third-party host (TV1). They are almost certainly unlicensed restreams.

The optional add-on lanes (CS, AS, LS, FS and SV) and Score808 are aggregators of the same kind as Streamed. Expect them to disappear the same way.

## Options, best first

### 1. "Where to watch": legal listings plus deep links

For each fixture, show which licensed broadcaster carries it in the viewer's country, and open that app with a deep link. This covers every match and needs no stream rights. It also does not break when a pirate host closes.

- **[TheSportsDB](https://www.thesportsdb.com/documentation)** has TV-schedule endpoints. They filter by date, sport, country and channel, and look up the channels for one event. The free key allows only 1 result. A useful volume needs Premium or Business: up to 1,500 results, the v2 API, and 100 to 120 requests a minute. Commercial terms are on its pricing and terms pages; read them before building.
- Rights tables change every season, for example the [2026 World Cup broadcasters](https://en.wikipedia.org/wiki/2026_FIFA_World_Cup_broadcasting_rights). They are good for checking the listings, but they go stale too quickly to ship as data.
- **Fit with Fotty.** It suits the existing fixture catalogues and match pages. The Watch button would become "Watch on Peacock" or a similar label when no free stream exists.

### 2. Official live streams on YouTube, embedded

Many rights holders stream selected matches free on their own YouTube channels. Examples are [FIFA+, Concacaf, the AFC, federations and leagues](https://cybernews.com/stream-online/how-to-watch-football-youtube-for-free/), and some cricket boards and smaller tournaments ([cricket listing](https://thesportscommons.com/sport/cricket/)). [DAZN's free tier](https://www.dazn.com/en-US/news/rugby-union/live-sport-watch-free-dazn-this-weekend-t3r/1dc0rl3jyujjo1pijlrgvv7mop) also streams selected events, such as all of the FIFA U-17 Women's World Cup and [one Serie B game a week in Italy](https://www.telecompaper.com/news/dazn-italia-to-air-serie-b-games-on-free-tier--1580582). That tier has no public API, so it is deep-link only.

- **How.** Discover live broadcasts from an allowlist of verified official channel IDs through the YouTube Data API, then play them in YouTube's embedded player.
- **[YouTube's embedding rules](https://developers.google.com/youtube/terms/required-minimum-functionality)** apply:
  - use the player unmodified, with no overlays on it;
  - keep the player at least 200×200 px (480×270 for 16:9);
  - autoplay only when the player is more than half on screen;
  - send a Referer header that identifies the app.

  Fotty's own native player, relay and source switching cannot be used on these streams.
- **Limits.** Coverage is selected matches only, and often geo-restricted. For example, [CazéTV](https://cybernews.com/stream-online/how-to-watch-football-youtube-for-free/) has every La Liga match free, but only in Brazil.

### 3. Free ad-supported channel apps (deep link)

[Pluto TV, Tubi, The Roku Channel and Samsung TV Plus](https://en.wikipedia.org/wiki/Free_ad-supported_streaming_television) carry sports channels, such as Pluto's NFL, Champions League and CBS Sports HQ channels. They also carry some live events: Tubi had selected 2026 World Cup matches in the US, and [Samsung TV Plus streams every MotoAmerica race](https://www.pocket-lint.com/samsung-tv-owners-just-got-a-new-free-live-sports-channel/) in 2026 and 2027. Sling Freestream and Red Bull TV are similar.

- **Deep-link to these apps.** Don't play their streams inside Fotty. Their HLS streams depend on each platform's own ad insertion and terms, even when the channel itself is free.

## Recommendation

1. **Build "where to watch" first.** It is the only option that covers every fixture legally. Start with TheSportsDB's TV schedule on a paid key, after checking its commercial terms.
2. **Then add official YouTube live** for the free matches. Use an allowlist of verified rights-holder channels, played in YouTube's own player.
3. **Decide what to do with the paid channels and aggregator lanes in the TV list.** Keeping them carries the same legal and reliability risk as Streamed.

## Sources

- [Free ad-supported streaming television (Wikipedia)](https://en.wikipedia.org/wiki/Free_ad-supported_streaming_television)
- [Samsung TV Plus MotoAmerica channel (Pocket-lint)](https://www.pocket-lint.com/samsung-tv-owners-just-got-a-new-free-live-sports-channel/)
- [Free football on YouTube 2026 (Cybernews)](https://cybernews.com/stream-online/how-to-watch-football-youtube-for-free/)
- [Free official cricket streams (The Sports Commons)](https://thesportscommons.com/sport/cricket/)
- [DAZN free live sport](https://www.dazn.com/en-US/news/rugby-union/live-sport-watch-free-dazn-this-weekend-t3r/1dc0rl3jyujjo1pijlrgvv7mop)
- [DAZN Italia free Serie B (Telecompaper)](https://www.telecompaper.com/news/dazn-italia-to-air-serie-b-games-on-free-tier--1580582)
- [TheSportsDB API documentation](https://www.thesportsdb.com/documentation)
- [YouTube embedded player minimum functionality](https://developers.google.com/youtube/terms/required-minimum-functionality)
- [2026 FIFA World Cup broadcasting rights (Wikipedia)](https://en.wikipedia.org/wiki/2026_FIFA_World_Cup_broadcasting_rights)
