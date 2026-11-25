# LiveNetTV APK review — 30 October 2026

REA 6.4.0 inspected the owner-supplied APK with the existing JADX 0.7.1 engine, one worker and a 384 MiB heap. No software installation, APK execution, target API/media fetching, credentials extraction or device interaction was required. The package identity is `com.playnet.androidtv.ads`, version 5.0.1 (56); the filename alone does not authenticate its publisher. Signature verification was not performed.

## Observed evidence

The archive inspection and Android package inspection are identified in `rea-summary.json`. The engine exposes only 16 bootstrap/protected/stub classes. Packaged IJK/FFmpeg libraries do not establish actual playback performance or support for any particular current delivery.

A bounded independent parser decoded 232 compiled layout/menu/XML members (336,676 uncompressed bytes) and the typed resource table. The resource receipt retains member hashes and offsets against the APK SHA-256. It establishes declarations for separate channel/event navigation, alternate-link selection, retry/loading states, contextual channel reporting/service status, a player that fills its parent, and optional quality choices. These are static declarations; reachability, runtime transitions, automatic bitrate adaptation and actual channel availability were not observed.

## Comparison with Fotty

- **Keep match → Watch → existing options.** Channel availability and exact event/programme evidence must remain separate. Fotty already has typed channel/event/programme records and fresh guarded source selection; the APK does not establish a superior matching algorithm.
- **Remove the unconditional channel diagnostic.** `SportsDashboardView.cricketDiscovery` displayed a blanket programme-unconfirmed subtitle independent of accepted programme evidence. That claim is redundant for browsing channels and can contradict a verified programme. It is removed in the current authorised shared-Watch candidate; fixture Watch eligibility still depends on real association evidence.
- **Improve empty-source explanations later.** The existing picker receives sessions and a checking flag, so its empty state cannot clearly distinguish an observed provider failure from a genuinely unlisted event. A typed result from existing discovery would improve the same picker without adding a Check Streams action. This is a recommendation, not implemented by this research.
- **Consider remembering quality intent on this device.** Fotty already has Auto/Data Saver and uses real HLS variants. Its quality intention deliberately resets between items. A device-local preference could preserve user intent, while fixed-quality streams remain usable. This is a product choice, not a confirmed defect or implemented change.

## Unknowns and limits

The APK's catalogue refresh, server database, cache invalidation, source matching, retries and fallback algorithms were not recovered. No claim is made that it uses a shared registry, that Auto means adaptive bitrate, that its streams work in Fotty, or that it can replace Fotty's source services. No new source is qualified or enabled by this static review. FPL, multi-stream, the owner's phone and TestFlight remain outside this work.
