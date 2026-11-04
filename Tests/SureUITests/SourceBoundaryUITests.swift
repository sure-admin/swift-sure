import XCTest

final class SourceBoundaryUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor
  func testConnectOpensLoginAndCogOpensSettings() throws {
    let app = launch("connection-routing")
    XCTAssertTrue(app.buttons["Connect to Sure"].waitForExistence(timeout: 10))
    app.buttons["Connect to Sure"].tap()
    XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.secureTextFields["Password"].exists)
    XCTAssertTrue(app.buttons["Continue with Apple"].exists)
    XCTAssertTrue(app.buttons["Continue with Google"].exists)
    XCTAssertFalse(app.navigationBars["Settings"].exists)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    app.buttons["Settings"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.textFields["https://demo.sure.am"].exists)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Connect to Sure"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "settings-from-cog"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testConnectPreservesSubscriptionGate() throws {
    let app = launch("connection-routing-locked")
    XCTAssertTrue(app.buttons["View subscription plans"].waitForExistence(timeout: 10))
    app.buttons["View subscription plans"].tap()
    XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.textFields["Email"].exists)
    XCTAssertFalse(app.secureTextFields["Password"].exists)
    app.buttons["Settings"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.textFields["Email"].exists)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
  }

  @MainActor
  func testSignInLightAppearance() throws {
    try checkSignInAppearance("sign-in-light")
  }

  @MainActor
  func testSignInDarkAppearance() throws {
    try checkSignInAppearance("sign-in-dark")
  }

  @MainActor
  func testSignInServerAttributionInBothAppearances() throws {
    for scenario in ["sign-in-light", "sign-in-dark"] {
      let app = launch(scenario)
      let attribution = app.descendants(matching: .any)["sign-in-server-attribution"].firstMatch
      XCTAssertTrue(attribution.waitForExistence(timeout: 10))
      for _ in 0..<3 where !attribution.isHittable {
        app.scrollViews.firstMatch.swipeUp()
      }
      XCTAssertEqual(attribution.label, "Sure server: demo.sure.am")
      XCTAssertTrue(attribution.isHittable)
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "\(scenario)-server-attribution"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      try app.performAccessibilityAudit(for: .sufficientElementDescription)
    }
  }

  @MainActor
  private func checkSignInAppearance(_ scenario: String) throws {
    let app = launch(scenario)
    let email = app.textFields["Email"]
    let password = app.secureTextFields["Password"]
    XCTAssertTrue(email.waitForExistence(timeout: 10))
    XCTAssertTrue(password.isHittable)
    XCTAssertFalse(app.buttons["Continue"].isEnabled)
    // Inspect gradient contrast in the attached screenshots; audit labels and sizing here.
    try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
    let emptyFields = XCTAttachment(screenshot: app.screenshot())
    emptyFields.name = "\(scenario)-empty-fields"
    emptyFields.lifetime = .keepAlways
    add(emptyFields)
    email.tap()
    email.typeText("user@example.com")
    XCTAssertEqual(email.value as? String, "user@example.com")
    email.typeText("\n")
    XCTAssertTrue(password.isHittable)
    password.typeText("Password1!")
    XCTAssertTrue(app.buttons["Continue"].isEnabled)
    if !app.buttons["Continue"].isHittable { app.scrollViews.firstMatch.swipeUp() }
    XCTAssertTrue(app.buttons["Continue"].isHittable)
    // Entered single-line fields may scroll their text; audit sizing before editing.
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  #if DEBUG
  @MainActor
  func testDebugUsageAnalyticsShowsConfiguredDestinations() throws {
    let app = launch("analytics-debug")
    let postHog = app.descendants(matching: .any)["posthog-build-token"]
    XCTAssertTrue(postHog.waitForExistence(timeout: 10))
    XCTAssertTrue(postHog.label.contains("phc_ui_fixture"))
    let sentry = app.descendants(matching: .any)["sentry-build-dsn"]
    XCTAssertTrue(sentry.waitForExistence(timeout: 10))
    XCTAssertTrue(sentry.label.contains("https://publickey@o1.ingest.example/42"))
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
  }

  @MainActor
  func testSubscriptionSheetKeepsPurchaseBarAtBottomWithoutTelemetryLinks() throws {
    let app = launch("subscription-sheet")
    let subscribe = app.buttons["Subscribe"]
    XCTAssertTrue(subscribe.waitForExistence(timeout: 10))
    XCTAssertTrue(subscribe.isHittable)
    XCTAssertFalse(app.buttons["Usage analytics"].exists)
    XCTAssertFalse(app.buttons["Diagnostics"].exists)
    XCTAssertFalse(app.staticTexts["Renews automatically unless cancelled."].exists)
    XCTAssertFalse(app.staticTexts["$0.99 every 1 month. Cancel any time."].exists)
    XCTAssertGreaterThan(subscribe.frame.maxY, app.frame.maxY - 80)
    let purchasePosition = subscribe.frame.minY
    app.scrollViews.firstMatch.swipeUp()
    XCTAssertEqual(subscribe.frame.minY, purchasePosition, accuracy: 1)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
  #endif

  @MainActor
  func testSynchronizedWalletUsesBackendCardAndSignedBalance() throws {
    let app = launch("wallet-synced")
    XCTAssertTrue(app.staticTexts["Synchronized Apple Card"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Apple Card Preview"].exists)
    XCTAssertFalse(app.staticTexts["Institution unavailable"].exists)
    XCTAssertTrue(app.staticTexts["Apple Wallet"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["-$125.00"].exists)
    XCTAssertTrue(app.staticTexts["Apple Card (Monthly)"].exists)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.staticTexts["Synchronized Apple Card"].tap()
    XCTAssertTrue(app.navigationBars["Synchronized Apple Card"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testOnboardingWalletPreview() throws {
    let app = launch("onboarding")
    XCTAssertTrue(app.staticTexts["Apple Card Preview"].waitForExistence(timeout: 10))
    app.buttons["Spending"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Wallet spending · On this device"].waitForExistence(timeout: 10))
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testConnectedAccountsIncludeWalletWhileReportingUsesSure() throws {
    let app = launch("connected")
    XCTAssertTrue(app.staticTexts["Sure Checking"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Apple Card Preview"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Apple Wallet, on-device account"].exists)
    app.buttons["Spending"].firstMatch.tap()
    XCTAssertTrue(app.buttons["About spending comparison"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Wallet spending · On this device"].exists)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testSpendingFailureCanRetry() {
    let app = launch("failure")
    app.buttons["Spending"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 10))
    app.buttons["Try again"].tap()
    XCTAssertTrue(app.buttons["Try again"].waitForNonExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Wallet spending · On this device"].exists)
  }

  @MainActor
  func testWalletRejectionShowsAccessibleProtocolCodeAndRepair() throws {
    let app = launch("wallet-rejection")
    let diagnostic = app.staticTexts["wallet-sync-batch-rejection"]
    XCTAssertTrue(diagnostic.waitForExistence(timeout: 10))
    XCTAssertTrue(diagnostic.label.contains("HTTP 422: invalid_payload"))
    XCTAssertTrue(diagnostic.label.contains("events[7].transaction.posted_at"))
    XCTAssertTrue(diagnostic.label.contains("A booked transaction has no posting date"))
    XCTAssertTrue(app.buttons["Repair Wallet sync"].exists)
    XCTAssertFalse(app.buttons["Sync Wallet accounts to your Sure family"].exists)
  }

  @MainActor
  func testWalletConsentPersistsAndWithdrawalCanBeCancelled() throws {
    let app = launch("wallet-consent", resetConsent: true)
    let label = "I understand this shares financial data with my Sure family"
    let toggle = app.switches[label]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    setWalletConsent(toggle, enabled: true)
    let enabled = NSPredicate(format: "value == '1'")
    expectation(for: enabled, evaluatedWith: toggle)
    waitForExpectations(timeout: 10)
    app.terminate()
    app.launchEnvironment["SURE_RESET_WALLET_CONSENT"] = "0"
    app.launch()
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "1")
    setWalletConsent(toggle, enabled: false)
    XCTAssertTrue(app.buttons["Keep synchronized transactions"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Delete synchronized transactions"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertEqual(toggle.value as? String, "1")
    setWalletConsent(toggle, enabled: false)
    app.buttons["Keep synchronized transactions"].tap()
    expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)
    waitForExpectations(timeout: 10)
    app.terminate()
    app.launch()
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "0")
  }

  @MainActor
  func testWalletEnrollmentShowsAccessibleProgress() throws {
    let app = launch("wallet-sync")
    let consent = app.switches["I understand this shares financial data with my Sure family"]
    XCTAssertTrue(consent.waitForExistence(timeout: 10))
    consent.switches.firstMatch.tap()
    let enroll = app.buttons["Sync Wallet accounts to your Sure family"]
    XCTAssertTrue(enroll.isEnabled)
    enroll.tap()
    XCTAssertTrue(app.descendants(matching: .any)["wallet-sync-enrollment-progress"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Sync Wallet accounts to your Sure family"].exists)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    app.buttons["Finish fixture enrollment"].tap()
    XCTAssertTrue(app.buttons["Sync Wallet accounts to your Sure family"].waitForExistence(timeout: 10))
  }

  @MainActor
  private func setWalletConsent(_ toggle: XCUIElement, enabled: Bool) {
    let control = toggle.switches.firstMatch
    let start = control.coordinate(withNormalizedOffset: CGVector(dx: enabled ? 0.25 : 0.75, dy: 0.5))
    let end = control.coordinate(withNormalizedOffset: CGVector(dx: enabled ? 0.75 : 0.25, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: end)
  }

  @MainActor
  private func launch(_ scenario: String, resetConsent: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SURE_SCENARIO"] = scenario
    app.launchEnvironment["SURE_RESET_WALLET_CONSENT"] = resetConsent ? "1" : "0"
    app.launch()
    return app
  }
}
