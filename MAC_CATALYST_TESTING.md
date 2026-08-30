# Mac Catalyst Testing

Fotty now has a repeatable Mac test path through a proper Mac Catalyst build.

## Build and launch

From the repo root:

```bash
tools/mac-catalyst-run.sh
```

This will:

1. build `Fotty`
2. target `platform=macOS,variant=Mac Catalyst`
3. open the built `.app`

## Useful variants

Build without launching:

```bash
tools/mac-catalyst-run.sh --no-open
```

Use a different configuration:

```bash
tools/mac-catalyst-run.sh --configuration Release
```

## Manual Xcode route

1. Open `/Users/jelani/Documents/Development/Fotty/Fotty.xcodeproj`
2. Select scheme: `Fotty`
3. Select destination: `My Mac (Mac Catalyst)`
4. Press Run

## Current recommendation

Use the Mac Catalyst destination for Mac testing.

Do not use the `Designed for iPad` destination as the primary Mac test path. That route was unstable on this machine and could make the Mac feel frozen under the Xcode wrapper runtime.
