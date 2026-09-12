# Purchase access before Sure connections

Status: draft for product decisions; implementation is not authorized yet.

## Objective

Require a verified in-app-purchase entitlement before this Apple client connects
to a Sure backend. Keep Sure credentials and purchase ownership independent.
Buying client access does not create a Sure account or purchase server hosting.

## Current integration points

- No StoreKit or RevenueCat integration is present.
- `AppDefinition` restores stored credentials into `SureSession` at startup and
  composes separate authentication and authenticated API transports.
- `SureConnection` supports API keys, passkeys, passwords, and provider SSO.
- `ApplicationConnectionLifecycle` starts finance refresh and notification work
  after connection. Watch insights originate from the phone.

## Decisions needed before implementation

1. Permanent non-consumable unlock or auto-renewable subscription? Specify price,
   subscription periods, and any introductory trial.
2. Does one purchase cover all supported Sure servers and Apple devices? Proposed:
   yes, including self-hosted servers, with no per-server charge. Decide Family
   Sharing separately. This does not add simultaneous multi-server support.
3. What remains free: local Wallet features, local assistant, cached financial
   data, or a preview? Should even server discovery/compatibility checks wait for
   purchase? Proposed: no Sure network contact until entitled.
4. Must existing users purchase immediately, or receive grandfathered access?
   Decide how development and TestFlight testing should work without a production
   bypass. Existing local credentials alone are not proof of purchase.
5. On expiration/refund, should cached data remain readable? Proposed: preserve
   credentials, suspend backend access, and permit local sign-out/data removal.
   Subscription grace-period access follows Apple's verified entitlement state.
6. Use direct StoreKit 2 or RevenueCat? Proposed: direct StoreKit 2 for an Apple-only
   client unlock, without a new billing server or sending purchase data to Sure.

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
4. Define push cleanup on entitlement loss: either allow narrowly scoped
   unsubscription/revocation traffic or defer server cleanup if absolutely no
   backend traffic is permitted. Local logout must always work. Stop new Watch
   insight delivery and apply the agreed cached-data policy to Watch state.
5. Design the purchase screen using the native-app-design and Apple HIG skills.
   Explain that purchase unlocks the client and a separate Sure server/account is
   required. Show localized StoreKit prices, restoration, retry, and subscription
   management/terms where applicable. Resume the intended connection after access
   is granted. Support Dynamic Type, VoiceOver, iPad, and Mac. Keep Watch purchasing
   on the companion app and explain access state on Watch.
6. Configure real products through `appStoreConnect/` using the App Store Connect
   skill; verify bundle identity, platform availability, metadata, and review
   notes. Submit the first products with an app binary. No StoreKit configuration
   files, external-service setup, or product publication during planning.

## Validation and acceptance

- Deterministic Swift Testing fakes prove zero Sure requests before access is
  granted, including restored credentials, callbacks, refresh, and background work.
- Test success, cancellation, pending approval, unverified transactions, restore,
  relaunch, expiry/refund, grace, offline state, account changes, and racing access
  loss against authentication/requests. Verify resumption without double requests.
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
