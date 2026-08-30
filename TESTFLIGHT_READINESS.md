# Fotty TestFlight Readiness Checklist

## Channel and build

- Default: the existing **internal TestFlight** group, including the owner's devices.
- Use scheme `Fotty`, configuration `Release`, generic physical iOS destination, and `ExportOptions-TestFlightInternal.plist`.
- Fotty has one Release product graph. TestFlight and local Release builds use the same user-facing sports names and functionality.
- No external review submission, tester/role changes, direct device install, or Git publication is implied.

## Before archiving

- Sign in to App Store Connect and check the latest uploaded build; do not assume the local build number is current.
- Use `tools/set-version.sh` for one higher, unused Apple build number across app and extension. Keep the marketing version for iterations within the same beta release scope.
- Record passing unit/policy and relevant Catalyst UI evidence for the source being released. Compile generic iOS; no simulators on this Mac.
- Check disk space. Reuse one owned temporary DerivedData/archive/export root, build sequentially with two jobs, and install an exit/interrupt cleanup trap.

## Archive and upload

- Verify matching app/extension bundle versions, identifiers, signatures, deployment targets, production configuration and current icon.
- Automatic signing may use the existing Xcode developer account. Never put credentials in source or logs.
- Upload with symbols and `testFlightInternalTestingOnly = true`; keep Xcode's automatic build-number management disabled so source and upload agree.
- Record Apple's upload result. Then check processing completion and availability to the existing internal group; these are separate states.
- Add concise What to Test notes for the exact build, including changed screens and known limitations.
- Delete owned temporary build/export/archive artifacts after completion or failure and recheck free disk space. Keep only small release records.

## Through TestFlight, before wider invitations

- Verify version/build, launch and preserved local preferences on a supported iPhone and iPad (iOS/iPadOS 26.4+).
- Check Home, Matchday, FPL and Settings; narrow/Zoomed iPhone, large text, keyboard dismissal and iPad rotation.
- Exercise real provider playback controls and lifecycle when an active feed can be independently decoded. Report provider failures separately from app faults.
- Follow `docs/BETA-TESTER-GUIDE.md`, including one confirmed received TestFlight feedback report before widening the group.
- Keep internal users' access limited to their role. Internal testing is not App Store approval, and builds expire after 90 days.

The full release sequence and source-publication boundary are in `docs/RELEASE-PROCESS.md`.
