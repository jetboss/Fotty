# Build192 — enabled registry, TV1 and buffering recovery

Completed30October2026 on Jet iPad. Phone189, FPL, multi-stream and shared TestFlight121 were left alone.

- Protected PR105 merged as c4cb85e. All7checks pass. The shared broadcast registry is deployed and ON, with automatic Cloudflare cron/alarm collection. The existing watchdog is active against the new version; original activation,125notices, prior namespaces and settings were retained.
- First cloud drain retained743observations from7reviewed families. The installed native app accepted the real cloud snapshot:14provider scopes/743observations/12links. Current links remain3conflicting/9needsVerification; none is falsely advertised as listed. StreamEx and Score failures do not erase other observations.
- Signed Release192 is installed.399focused native tests passed,0failed,1explicitphysicalskip. The initial run's2harness failures were corrected (missing shared fixture copy and a stale assertion about the nested Settings route), then the full selected gate reran successfully. Independent source review caught and fixed the retry and90second TV1 reselection traps.
- TV1 is enabled on Jet. Normal Willow Watch automatically selected it, with TV1 andCS1 separately shown in the normal picker. Correct Willow Live/South Africa–Australia programme and advancing decoded picture held over90seconds. Native fullscreen, pause/resume, systemPiP visibly over Home for over60seconds and systemRestore without prior app activation passed. Player/item object identity was not independently instrumented.
- Selecting CS1 reproduced a decoded stall at15:59:57UTC. Fotty automatically switched toTV1 and decoded again at16:00:03UTC:about5.25seconds, including fresh renewal ofTV1's expired90second binding. TV1 remains enabled and playing after the gate. CS itself is not called repaired or flawless.

The guarded frozen-window descriptor retry passed deterministic compiled regressions; this physical CS selection had already refreshed its expired binding, so a second automatic descriptor retry was correctly not claimed. Finite evidence from existing requests captured11media-playlist samples, matching upstream/rewritten metadata, a6second target,8.915seconds unchanged at the failure and one AVPlayer stall. Observed14.67Mbps versus indicated3.52Mbps is a useful sample, not proof that network variability is impossible or a conclusive root cause. No URLs/tokens/bodies enter retained diagnostics.

Native Auto/Saver still use actual HLS variant ladders. TV1's one720p rendition remains a valid playable option. No resolution tiers were fabricated, no source was excluded for being fixed quality, and no global buffer target was inflated. Controlled weak-network ABR proof remains open.

The inspected Fox programme feed was empty. No guessed EPG, Willow timezone or Test-day association was enabled. Main-Willow channel playback does not qualify Premier League/Champions League or prove an exact cricket fixture link. Those source-qualification gates remain explicit.

Small redacted JSON receipts in this folder retain build/test/configuration/normal-playback evidence. Raw preferences, source metadata, logs, signed binaries and Xcode output belong only to the owned temporary gate and are cleaned afterward.
