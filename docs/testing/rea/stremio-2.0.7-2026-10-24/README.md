# Stremio Apple2.0.7 static REA evidence

24 October2026. Public reference artifact only; no Fotty/private-device data.

The official Stremio downloads page currently links this exact package:

`https://dl.strem.io/apple/macos/release/Stremio-2.0.7-22-8-1-c8b501b6e2d1.zip`

- Download:128,866,900 bytes; SHA256
  `687159047c8bf5a935afd14ecd796efb30cea857bb7ab06d6e6903299a443be3`.
- Parsed bundle: `com.stremio.pal`,2.0.7(22), executable `Stremio`.
- Main Mach-O SHA256:
  `7ace606680feb99b9797925832fc5b3c60dda81b8d1d72faa060037e52f9e3f6`.
- REA6.4.0 via its already installed public launcher. No engine installation,
  native application launch, account access, device interaction or target mutation.

Canonical generated Evidence is retained here without the CLI wrapper. Temporary
artifact paths in provenance describe the analysis input, not files left on disk.
The archive and334.7MB regular-file extraction are temporary and removed after
inspection. These small records are intentional reusable receipts, not caches.

| File | Operation / Evidence ID |
| --- | --- |
| inventory.json | inspect_artifact: ev_4b5cefcf4d524e92cc5d147651a0f394b6ff5d6183429a75489179469ae009eb |
| plist.json | inspect_plist: ev_5d5d5032c6399be25f4781521f6c1c83bace512b91219227efcac39ed183f591 |
| macho.json | inspect_macho: ev_82b1e1702c5c593059290ae47f9aee553dcca4ebcf06125c6371dfa3674fd330 |
| ksplayer-plist.json | inspect_plist: ev_2be32faac81950a1fd37679b81766dc55d9b722484321d88d6aba03f2080f46c |

Inventory's nested complete artifact graph is
`ev_60f9314506bca2147ef2d8e896b862ade5a69c5376eaaffa082425608c29e488`,
manifest `agm_b7051f6a3fb81f14c4b67222962f799874570b2ea6e917a9dd17839eafa24f41`:
385 nodes,414 occurrences,404 edges. ZIP central-directory coverage is not native
behavior coverage. Extraction Evidence
`ev_39fd3c3e3e99445cf502d233eebcd985814e20c85447b869223e13470edc5349`
reports verified containment; no extracted application is retained.

Confirmed: the actual main image links UIKit through iOSSupport, AVKit,
AVFoundation, VideoToolbox and bundled KSPlayer. KSPlayer's bundle reports1.0(1),
which does not identify its upstream commit or license arrangement. Imports,
framework names and declared background/PiP metadata do not prove selected
engine, playback policy, speed, source support or active behavior.

The announced Apple2.1 release is a separate reference. This downloaded2.0.7
archive cannot establish2.1 implementation or visuals. Native function analysis
providers are not configured; no decompilation, call graph, runtime scenario,
native2.1 reconstruction or complete Stremio audit is claimed. See the active
2.5 scope in the Stremio usability review for questions still open.
