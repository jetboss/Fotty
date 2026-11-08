# Sports TV follow-up, November 3 (Tobago)

Fresh CS NETWORKS searches, same-ID metadata and advertised stream lookups; bounded Mac master, variant and media checks. No route was enabled or installed. Decoding one sample does not establish sustained station playback or a match assignment.

| Exact station edition | Outcome |
|---|---|
| FS1 (US) | The CS-origin route returned a picture with FS1 branding, Arizona State 17–BYU 20 in the fourth quarter. Fotty's existing TV24 uses a different delivery host. Operational independence is unknown. First candidate for a native backup test. |
| Sky Sports Main Event (UK) | A compatible CS-origin route showed tennis and Sky Sports branding, Halys–Fery. The external CDN route did not complete the bounded segment check. Candidate for a station tune only. |
| Fox Cricket (Australia) | Multiple advertised routes. One returned 404 at the master. An alternative returned media but the sampled decoded picture was black. Correct visible programme and sustained native playback are open. |
| TNT Sports 4 (UK) | Catalog and metadata matched. A route returned transport-stream bytes, but the subsequent bounded decode produced no picture. Pending. |

Before adding FS1 as a backup, test the US station through Fotty’s guarded resolver on Jet, sustain both delivery paths, force the primary unavailable, and check that the same station returns automatically. Keep ordinary source switches and provider opt-ins intact. Do not claim live football or cricket coverage from a station title alone.
