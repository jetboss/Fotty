# Device compatibility assessment

Date: 28 August 2026. Outcome: **an unchanged-source iOS 18 compile probe passes**.
This is not an older-device support release or runtime certification.

## Current promise and observed devices

Build 43's signed/uploaded app and Live Activity/widget extension both retain
minimum OS **26.4**, with iPhone/iPad device families unchanged. No source target
or entitlement was lowered by this assessment.

App Store Connect's existing-group inventory shows build 42 installed on an
iPhone 15 Pro Max with iOS 27.0 and an iPhone 16 Pro Max with iOS 26.6. The first
tester has one additional device in Apple's inventory, not independently
identified in this check. There is no new iPad or older-OS acceptance evidence.

## Evidence

- The current app uses SwiftData/Observation and modern SwiftUI presentation.
  FPL scroll restoration uses `ScrollPosition` and `onScrollGeometryChange` in
  `Fotty/Features/FPL/Views/FPLMainView.swift`.
- The installed Xcode 27 SDK explicitly marks `onScrollGeometryChange` available
  from iOS 18.0. A source scan found no use of the newer glass APIs, but a string
  scan alone cannot prove all availability requirements.
- After completing the normal 26.4 archive/upload, run a separate unsigned
  generic-device Release build with the command-line override
  `IPHONEOS_DEPLOYMENT_TARGET=18.0`. The normal app and dependent extension build
  **exit 0** with the same source/config/test fingerprint:
  `a16b9cc56743f87974eb05253781179cd627273bbe8552ac15ab047b03cd9fae`.
- This uses the same bounded DerivedData directory, two sequential build jobs,
  no simulator and no direct install. The diagnostic output is removed.

## Recommendation

Treat **iOS/iPadOS 18** as the first candidate floor to qualify, rather than
assuming 26.4 is essential. Do not advertise support until a deliberately
lower-target candidate has passed the release gates and real older hardware.
This potentially expands the audience without adding a feature or subscription.

Required before changing the product promise:

1. Identify an actual available iPhone and iPad running the proposed older OS;
   compare their capability with the intended testers. A device limited below
   iOS 18 would not be helped by this candidate floor.
2. Change all app/extension/test targets consistently in a new candidate. Run
   full policy/UI gates, normal and Review Safe compilation, and signed archive
   validation with the new minimum; this assessment only probes normal Release.
3. Verify fresh install and update-with-retained-data, SwiftData persistence,
   FPL scroll/keyboard behavior, Light/Dark/System, reminders and widget rendering.
4. Qualify real WebKit playback, controls, foreground/background and native
   PiP where compatible on the older device. A newer SDK compile cannot emulate
   an older WebKit engine or lower-memory hardware.
5. Record battery/heat, small-screen/large-text layout and unacceptable regressions.
   Broaden only to the hardware/OS combinations actually validated.

No iOS 17-or-earlier probe, older-device installation, Review Safe 18 archive,
public compatibility announcement or minimum-target source change was made.
