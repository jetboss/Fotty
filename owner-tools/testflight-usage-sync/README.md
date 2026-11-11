# Fotty TestFlight participation dashboard

This owner-only tool answers one narrow question: which invited testers are actually using the TestFlight build?

It reads Apple’s existing TestFlight roster and beta usage metrics. It does **not** add analytics to Fotty, ask testers for codes, alter the iOS privacy manifest, or send tester data to another service.

## What it shows

- Invitation state: Invited, Accepted, Installed, or Revoked
- Sessions in Apple’s trailing 7-day and 30-day windows
- 30-day crash and feedback counts
- Apple’s reported build and device fields when available
- Factual participation groups:
  - **Recently active**: at least one session in 7 days
  - **Used this month**: no session in 7 days, but at least one in 30 days
  - **No recent sessions**: installed, but zero sessions in 30 days
  - **Not installed**: current state is not Installed

A session does not reveal which Fotty feature was used, how long the app stayed open, or whether playback succeeded.

## Private credential setup

Apple requires a JWT signed with an App Store Connect API key. Prefer an individual key or the least-privileged role that can read TestFlight tester information. Apple documents Account Holder, Admin, App Manager, Developer, and Marketing as roles that can view tester information.

Never copy the `.p8` key into this repository. Store it in a private location and expose only its absolute path through environment variables:

```sh
export APP_STORE_CONNECT_APP_ID=6805561883
export APP_STORE_CONNECT_ISSUER_ID='your-issuer-id'
export APP_STORE_CONNECT_KEY_ID='your-key-id'
export APP_STORE_CONNECT_PRIVATE_KEY_PATH='/private/path/AuthKey_your-key-id.p8'
```

The key file can only be downloaded once. Revoke it in App Store Connect if it is ever exposed.

## Refresh and build

From this directory:

```sh
node scripts/fetch-usage.mjs
node scripts/build-live.mjs
```

The fetch writes names, email addresses, and usage counts only to `.local/testflight-usage.json`, with restrictive file permissions. `.local`, key files, environment files, and the dashboard `dist` directory are ignored by Git.

The live build temporarily supplies the private snapshot to the dashboard builder, restores the tracked synthetic fixture in a `finally` block, and leaves the private compiled dashboard only in `../testflight-usage-dashboard/dist`. Do not publish that directory.

Serve the completed directory only on loopback:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory ../testflight-usage-dashboard/dist
```

Then open `http://127.0.0.1:8765/`.

## Verification

```sh
node --test tests/*.test.mjs
```

The tracked dashboard fixture uses only invented `example.invalid` identities. Real tester data is intentionally absent from source control.

## Apple sources

- [Read beta tester metrics for an app](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-metrics-betatesterusages)
- [Beta tester resource](https://developer.apple.com/documentation/appstoreconnectapi/betatester)
- [View and manage tester information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-and-manage-tester-information)
- [Create App Store Connect API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
