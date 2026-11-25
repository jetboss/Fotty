# Football before kickoff — 5 November 2026

The TENIES public TV catalog advertised the exact UK editions of Sky Sports Premier League and TNT Sports 4. Both station metadata endpoints returned the expected station title and a direct HLS playlist. Each playlist returned HTTP 200 and HLS content. They use distinct station paths on the same CDN. Sky previously produced footage of an archive match. Neither station has passed live PL/UCL acceptance on this build.

The app resolves fresh TENIES station metadata for TV25 and TV26 through Sports TV and its existing reviewed-channel relay. The channel identity, media origin, path, query shape and public headers are checked before playback. The private station install is separate from any tester distribution.

On 5 November the league feed and Sky's date-specific guide uniquely agreed on Everton–Coventry, Friday 6 November. Sky Sports Premier League and Main Event both start coverage 19:00 UTC; kickoff is 20:00 UTC. The guide audit recognizes the new station. This receipt is not an active cloud registry link. TNT Sports 4 has no confirmed assignment for Arsenal–Dortmund from this check.

The TENIES soccer catalog returned zero events. Five CNC event catalogs were sampled; no reviewed row confirmed the target fixtures. StremVerse's similarly named competitions included the Nepal Premier League and AFC Champions League Two. The public Nebula manifest offered configuration. No fixture mapping was inferred from those names.

On free Jet, test normal Watch and separately verify the station if missing from the picker. Record initial and replacement sources, first correct picture, commentary evidence, 90-second progress and time to automatic recovery after a scoped outage if an independent working route exists. Local follow-ups were created for 6 November and 24 November at 16:05 Tobago. Preserve source preferences and leave TestFlight for the owner's release decision.

Private normal Release 243 was signed, installed and launched on Jet. Device inventory confirmed 3.0.0 (243). Final focused Catalyst tests: 58 passed, zero failures. The first executable run had one outdated inventory-count assertion, corrected for the two new stations. Live match acceptance and tester distribution are pending.

Follow-up, 5 November. The default StremVerse live/Xtra pages omitted Everton, but an advertised targeted search in Xtra returned Everton vs Coventry City, dated 6 November. Same-ID metadata agreed. Its stream response contained one external “Token Required” entry and zero native deliveries. Use targeted search at kickoff. Nebula's shared public manifest now explicitly says its shared free install ended and points to private configuration. Both providers are on the existing Everton acceptance checklist alongside AS and every enabled source. Record access separately from playback.
