# iPhone Manual Deploy

This repo now includes a repeatable device deploy script:

[`tools/ios-deploy-device.sh`](/Users/jelani/Documents/Development/Fotty/tools/ios-deploy-device.sh)

## Quick start

From the repo root:

```bash
tools/ios-deploy-device.sh
```

That will:

1. build the `Fotty` scheme for a physical iOS device
2. find the first paired iPhone destination
3. install the app with `devicectl`
4. launch `com.jelani.Fotty`

## Useful commands

List paired devices:

```bash
tools/ios-deploy-device.sh --list-devices
```

Deploy to a specific phone:

```bash
tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
```

Reuse the last build and just reinstall:

```bash
tools/ios-deploy-device.sh --skip-build
```

Install without auto-launching:

```bash
tools/ios-deploy-device.sh --no-launch
```

## Notes

- The phone must be connected, paired, and unlocked.
- If iOS refuses the install because the developer image cannot mount, unlock the phone and retry.
- Default bundle ID: `com.jelani.Fotty`
- Default scheme/configuration: `Fotty` / `Debug`

## Current device

The last successful physical-device deploy in this thread used:

- device UDID: `00008130-000544A0212A001C`
- bundle ID: `com.jelani.Fotty`

So your fastest repeat command is:

```bash
tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
```
