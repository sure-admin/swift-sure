# FinanceKit device testing

Use the `financekit-background-sync` branch for PR #16. The current feature is
foreground Wallet sync; the background extension is not included in this branch.

## Build and install

Generate the project, open `Sure.xcodeproj`, select the **Sure** scheme and your
physical iPhone, and select your development team for both Sure and Sure Watch.
Run from Xcode. Do not commit the generated project or local signing settings.

```sh
xcodegen generate --spec Project.json
xcodebuild -project Sure.xcodeproj -scheme Sure -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/Sure-device \
  DEVELOPMENT_TEAM='<your-team-id>' -allowProvisioningUpdates build
```

The development profile for `am.sure.insights` must include FinanceKit
`financial-data`, `group.am.sure.insights.financekit`, and the shared Keychain
access group. A successful unsigned build alone does not validate provisioning.
Xcode can refresh stale profiles when the capabilities are approved for the App
ID. Check `NSFinancialDataUsageDescription` in the generated app plist as well.

Use an eligible iPhone on iOS 18 or later with authorized Wallet accounts. The
app checks FinanceKit availability at runtime. Local Wallet preview remains free;
remote sync additionally requires a verified subscription, an authenticated Sure
connection, preview access on the test server, and explicit family-data consent.
Use a disposable test family with the protocol-2 backend described in
[the contract baseline](SureContractBaseline.md); the pinned main revision alone
does not include these experimental endpoints.

## Device checks

1. On a fresh install, verify that local Wallet preview works without a Sure
   subscription or login. No financial records should upload.
2. Connect to the test server with an active subscription. Grant Wallet access
   and consent to family sharing. Start enrollment; the button should become
   accessible progress and repeated taps must not create extra connections.
3. Tap **Sync now**. Verify that Sure receives the selected accounts and source
   records. Check the separate accepted and imported timestamps against Sure.
4. Relaunch the app. It should recover the existing publisher and health rather
   than offer duplicate enrollment. Foreground activation should sync after
   entitlement refresh, with a one-minute debounce.
5. Exercise a server repair-required response and a local invalid-history-token
   outcome. Both must show **Repair required** until successful repair.
6. Interrupt connectivity during mapping, activation, upload, and receipt
   polling. Failed enrollment should attempt remote cleanup; accepted captures
   should remain pending until imported, without advancing the checkpoint early.
7. Log out while online and offline. Local publisher credentials, checkpoints,
   and pending captures must clear; no subsequent receipt request may use the
   old credential. Reopen the app and explicitly reconnect Wallet to access the
   free local preview again.
8. Let entitlement access lapse, then restore it. Downloaded records remain;
   connectivity suspends and resumes according to the verified entitlement.

Unattended, locked-device, and background-extension delivery are deferred to the
separate background-entitlement work. These checks require actual Wallet/server
interaction and are not claimed by simulator tests.
