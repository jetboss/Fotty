# Scoped source findings

28 October 2026, Tobago. These receipts cover metadata and bounded HLS-master checks; they do not establish decoded playback or correct on-screen programme content. The physical build receipt is maintained separately.

## CNC: correct fixture, empty delivery

Fresh official NHL status and the same-ID, explicitly dated CNC metadata corroborated Washington–Philadelphia at 28 October 23:30 UTC. CNC advertised a new Kinescope HTTPS delivery. Both its actual advertised headers and the relay-effective User-Agent-only headers returned the same 25-byte HLS document, with zero variants or media references. The final no-cache descriptor/master check at 29 October 01:28 UTC returned the same empty document. Its Date was current and Cache-Control specified no-store/no-cache; no Age header was supplied. Stale cache is not established.

This delivery remains pending a populated advertised master, a reviewed compatible contract and native qualification. It is not a global CNC failure or a playback pass. No keys or media segments were requested by these checks.

## CS: explicit date conflict retained

The CS catalog and same-ID metadata explicitly dated Philadelphia–Washington at 29 October 23:30 UTC. The authoritative NHL schedule dated that fixture at 28 October 23:30 UTC: a positive 24-hour contradiction. The app must retain that conflict rather than silently subtracting a day or inferring eligibility from names, countdown text or a LIVE marker. The advertised manifest supplied no source-code pointer in the bounded inspection. This blocks that particular CS NHL binding; it does not establish that every CS source is unavailable.

## Established-player lessons

The [Shaka REA receipt](/Users/jelani/Documents/Development/Fotty/docs/testing/rea/established-players-2026-10-28/shaka-delivery-presentation.json) retains exact shipped-artifact hashes, release/source correspondence and static-analysis limits. Relevant patterns are origin-scoped per-attempt headers, playlist-advertised transport authority and one media owner across presentation changes. Shaka does not provide sports-fixture truth or native AVKit/PiP proof. No broader host admission or timeline rewriting follows from this research.

The final MLB check independently reported Rays–Brewers still in progress at 29 October 01:36 UTC, matching the deployed live fixture. Receipt copies omit provider identifiers and contain no media URLs, tokens or device identifiers.
