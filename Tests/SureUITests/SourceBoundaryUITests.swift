import XCTest

final class SourceBoundaryUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

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
  private func launch(_ scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SURE_SCENARIO"] = scenario
    app.launch()
    return app
  }
}
