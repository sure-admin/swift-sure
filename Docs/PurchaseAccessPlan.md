# Purchase access before Sure connections

Status: initial runtime implementation and local product definitions completed.
Remote product setup, visual verification, and device sandbox purchase testing
remain pending; do not release this build before completing those checks.

## Objective

Require a verified in-app-purchase entitlement before this Apple client connects
to a Sure backend. Keep Sure credentials and purchase ownership independent.
Buying client access does not create a Sure account or purchase server hosting.

## Current integration points

- Direct StoreKit 2 integration verifies subscriptions and gates Sure access.
  RevenueCat and other billing services are not used.
- `AppDefinition` restores stored credentials into `SureSession` at startup and
  composes separate authentication and authenticated API transports.
- `SureConnection` supports API keys, passkeys, passwords, and provider SSO.
- `ApplicationConnectionLifecycle` starts finance refresh and notification work
  after connection. Watch insights originate from the phone.

## Agreed product decisions

- Auto-renewable monthly subscription at $0.99 and annual subscription at $9.99.
  Treat these as US-dollar base prices pending any correction; display Apple's
  localized prices. Both products belong to one subscription group at the same
  service level and unlock identical functionality.
- Enable Family Sharing on both products. Access covers supported Apple devices,
  all supported Sure backends, and all paid client functionality. No per-server
  charge; this does not add simultaneous multi-server support. Family members
  retain separate Sure credentials and financial data; sharing access never
  shares financial records automatically.
- Local Apple Wallet features and on-device Assistant calls remain free always.
  Purchase presentation must not block those paths.
- Offer a one-week free introductory trial on both plans so users can test their
  backend. An eligible user starts the trial through Apple's subscription flow
  before backend access begins. Display renewal price and trial eligibility;
  do not promise another trial when switching plans, devices, or servers.
  Apple limits introductory offers to one redemption per subscription group
  per eligible person. Family-shared entitlement grants access without requiring
  another purchase; use Apple's eligibility for anyone starting their own trial.
- After entitlement ends, previously synchronized data remains usable locally,
  including after relaunch. Stop all backend reads and writes in both directions,
  including future Apple Card uploads. Preserve credentials and local records;
  this is a suspended connection, not logout or cache deletion. Missing uncached
  data must be identified as unavailable offline rather than fetched or invented.
- Any app.sure.am subscription should eventually include client access, regardless
  of plan. This entitlement integration may be delivered later. Do not infer paid
  status from login success, a server URL, or an API key.

## Confirmed cancellation policy and implementation defaults

- Cancellation follows Apple subscription semantics: stop backend access when
  Apple's entitlement expires, not when auto-renewal is turned off. Paid/trial
  time remains usable while entitled. When renewal is cancelled, warn: "Sync will
  stop on [localized access end date]. Your downloaded data, local Apple Wallet
  features, and on-device Assistant will remain available." Derive the date from
  verified subscription state; do not invent a date if it is unavailable. Refund/revocation and loss of shared access
  suspend connectivity when verified by StoreKit. Honor verified billing grace;
  billing-grace configuration will be made explicit during product setup.
- Use Apple's StoreKit 2 directly. This is an open-source client: do not add
  RevenueCat or another third-party purchase SDK, billing service, account, or
  credential requirement. Purchase verification and restoration use Apple APIs;
  no new billing server is required. This is a product constraint, not a temporary
  implementation choice. The deferred app.sure.am entitlement integration remains
  separate and must not introduce RevenueCat into the client.
- No Sure discovery or compatibility traffic before an active trial or paid/shared
  entitlement. No production bypass for development/TestFlight; test with injected
  fakes and real sandbox entitlements.
- Credential entry itself is gated, not just the Connect action. Before Apple
  verifies an active trial, paid subscription, or Family Sharing entitlement, do
  not present API-key, email/password, passkey, or provider-SSO entry points. Do
  not accept credentials through paste/import, deep links, or another window.
  Starting checkout, a pending purchase, and an unverified transaction do not
  unlock authentication. Existing paid/shared access does not require a new trial.
- Guard authentication services as well as UI navigation. Stored credentials must
  not activate a session while locked. Block browser authentication launch, OAuth
  registration/token exchange, SSO callbacks, API-key verification, and token
  refresh until entitled. Recheck access after asynchronous work before committing
  any session; dismiss credential entry and discard uncommitted drafts if access
  ends. Keep free local features reachable without entering this flow.
- Defer server cleanup requests after entitlement loss under the strict no-backend
  rule. Suppress backend notification processing and registration, retain pending
  unsubscription cleanup for entitled access, and always permit local logout.
  Previously registered server pushes may still arrive until registration is
  removed; local suspension cannot guarantee the server stops sending them.

## Deferred hosted-subscription entitlement

Add an independently verified hosted entitlement source behind the same access
policy later. Inspect the pinned upstream contract before designing that flow;
do not invent a billing-status endpoint. The strict pre-entitlement authentication
gate has no hosted-login exception. Before implementing hosted inclusion, resolve
how existing subscribers can prove entitlement without violating that gate or
paying twice; any exception requires an explicit future product decision.
Define expiry, offline validity, family scope,
and cross-server scope for this source then. Until shipped, do not claim hosted
subscriptions already unlock the app or silently enroll those users in another
subscription. Make that temporary limitation clear in the connection flow.

## Implementation sequence after decisions

1. Define a typed access policy and injected entitlement service, composed at the
   app root. Represent checking, entitled, locked, and verification failure
   explicitly; model purchasing/pending/cancellation separately. Never use a
   preferences boolean as proof of purchase.
2. Implement StoreKit product loading, verified current entitlements, transaction
   updates, purchase completion, and user-initiated restoration. Handle revocation,
   expiration, billing grace, pending approval, unavailable products, and offline
   startup using verified StoreKit state. Do not grant access while verification
   is unresolved. Recheck on foreground and entitlement updates.
3. Enforce access before authentication and restored-session activation, plus at
   the Sure request boundary. Cover API-key verification, OAuth registration,
   password/passkey/SSO, callback completion, token refresh, finance, transactions,
   remote assistant, and push work. Cancel in-flight work and discard stale results
   when access is lost. Keep credential state separate from access state.
4. Audit persistence before enforcing suspension: current snapshot caching is not
   assumed to preserve every previously synchronized feature. Persist the domain
   data needed for existing local behavior (including fetched transaction history
   and remote conversation history where applicable), isolated by server/user.
   Preserve synchronized Watch data. Keep free local Wallet and on-device
   Assistant functionality working independently of backend access. Do not call
   logout/disconnect paths that clear these records on entitlement loss. Gate
   future upload workers through the same policy; adding uploads remains out of
   scope. Apply the notification cleanup policy above.
5. Design the purchase screen using the native-app-design and Apple HIG skills.
   Explain that purchase unlocks the client and a separate Sure server/account is
   required. Show localized StoreKit prices, restoration, retry, and subscription
   management/terms where applicable. Resume the intended connection after access
   is granted. Support Dynamic Type, VoiceOver, iPad, and Mac. Keep Watch purchasing
   on the companion app and explain access state on Watch.
6. Configure real products through `appStoreConnect/` using the App Store Connect
   skill; verify bundle identity, platform availability, metadata, and review
   notes. Configure both same-level plans, Family Sharing, and one-week trial
   offers. Submit the first products with an app binary. No StoreKit configuration
   files, external-service setup, or product publication during planning.

## Validation and acceptance

- Verify locked users cannot reach or enter any backend credentials through
  navigation, accessibility actions, another window, paste/import, or deep links.
  Test trial checkout pending/cancelled/failed states remain locked; only verified
  trial or paid/shared entitlement exposes authentication. Test stale auth
  callbacks and saved sessions cannot bypass the gate.
- Deterministic Swift Testing fakes prove zero Sure requests before access is
  granted, including restored credentials, callbacks, refresh, and background work.
- Test success, cancellation, pending approval, unverified transactions, restore,
  relaunch, expiry/refund, grace, offline state, account changes, and racing access
  loss against authentication/requests. Verify resumption without double requests.
- Test that cancelling renewal preserves access while still entitled; test
  expiration separately. Verify the end-of-period sync warning and date.
  Cover shared access grants/revocations, trial eligibility and conversion,
  switching plans without a second introductory offer, and restored purchases
  across devices. Verify retained data after relaunch and that free Wallet and
  on-device Assistant work without a subscription. Prove both upload and download
  entry points reject backend work when suspended (uploads when introduced).
- Build affected iOS, macOS, and Watch targets; run relevant iOS/macOS tests and
  Watch tests for changed Watch state. Inspect paywall interactions/accessibility.
- Exercise real sandbox purchases/restoration on a device through Run on… or
  TestFlight; Bitrig's built-in simulator cannot complete real sandbox purchases.
- No Sure API changes or financial mutations are expected. This gate controls
  this client's behavior; it does not impose licensing on a self-hosted server.

## References

- https://developer.apple.com/documentation/storekit/transaction/currententitlements
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase

- https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions
- https://developer.apple.com/app-store/subscriptions/

## Implementation status (2026-09-11)

Implemented: direct StoreKit 2 service, injected entitlement state and backend gate,
verified current entitlements and updates, purchase/restore/pending states,
entitlement expiry scheduling, cancellation-date messaging, and Family Sharing
entitlements. All credential screens and authentication methods are gated, as
are API-key verification, OAuth exchanges/refresh, and the shared network path.
In-flight requests are cancelled/discarded when access is revoked. Local features
stay reachable from the app tabs; saved connection state is retained on expiry.

Offline finance snapshots remain visible without refreshing their timestamps.
Authenticated GET responses are archived without credentials/headers in private,
backup-excluded files; cached responses are never used for authentication.
Transaction drill-downs retain their last fully fetched window across launches,
with an explicit downloaded-data label. Unfetched data remains unavailable.
Mac writes use private permissions; iOS writes retain complete file protection.
Foreground backend notifications are suppressed while access is suspended; the
server can still send previously registered pushes until cleanup is possible.

Monthly/yearly products, same service level, Family Sharing, US base pricing,
English localizations, review notes, and one-week trial offers in all 175 current
storefronts are staged and pass local App Store listing validation. Storefronts
were taken from Apple's App Store localization table:
https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations

Validation: Bitrig iOS/Mac builds passed (including the embedded Watch app).
Full unit suites passed on iOS (271 tests) and macOS (267 tests). Standalone
XcodeGen was unavailable, so CLI test validation used a temporary copy of the
existing generated project with new source membership and Info.plist values
from Project.json; no generated project is committed. Bitrig performed its own
project generation for the app builds.

Remaining before release:
- Complete on-device VoiceOver navigation and verify the loaded purchase plans
  after the staged products are applied. The simulator checks below cover the
  locked/unavailable state, not a completed purchase.
- Apply the staged product definitions to App Store Connect, complete product
  metadata/screenshots, and verify products reach Ready to Submit and load through
  StoreKit. The local listing validator does not verify remote readiness.
- Verify purchase, trial conversion, renewal cancellation, expiry, refund,
  restoration, and Family Sharing on physical devices using Apple's sandbox.
- Verify billing-grace configuration with the real product setup; the client
  already honors verified grace-period entitlement dates.
- Hosted app.sure.am subscription inclusion remains deferred as agreed.

## Simulator follow-up (2026-09-11)

The resumed iPhone simulator confirmed that the locked connection sheet exposes
no credential fields. Its controls and explanatory copy were inspected in light
and dark appearance and at the largest accessibility text size; the bottom
restoration and legal controls remain reachable by scrolling. Accessibility labels
were inspected. Enabling VoiceOver itself is unsupported by this simulator tool,
so spoken traversal remains a physical-device check. The free Assistant tab is
reachable without a subscription; no model request or financial data was sent.

This check found an idle/loading Overview on a locked cold start. `suspendSync()`
now cancels ongoing refreshes, ends loading indicators, and displays setup or the
subscription-required error when no snapshot exists, while preserving already
loaded snapshots and timestamps. The focused Mac finance suite passed (32 tests),
and Bitrig's iOS and Mac builds passed. The running simulator confirmed the
startup loading message was replaced by the setup state.

Initial review screenshots and manifests are prepared for both products. They
show the actual locked subscription screen with unavailable products; replace
these initial images with the loaded plans after remote product setup propagates.
The listing validates with the screenshot files present locally. Assets remain
excluded from git under the listing's standard policy. No App Store Connect
changes have been applied or submitted for review in this follow-up.
