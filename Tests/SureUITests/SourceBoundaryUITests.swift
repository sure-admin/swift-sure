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
  func testConnectedViewsUseSureData() throws {
    let app = launch("connected")
    XCTAssertTrue(app.staticTexts["Sure Checking"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Apple Card Preview"].exists)
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
  func testCashFlowChartAndAccessibleDetails() throws {
    let app = launch("connected")
    app.buttons["Cash flow"].firstMatch.tap()
    XCTAssertTrue(app.buttons["cash-flow-details"].waitForExistence(timeout: 10))
    let chartScreenshot = XCTAttachment(screenshot: app.screenshot())
    chartScreenshot.name = "Cash flow chart"
    chartScreenshot.lifetime = .keepAlways
    add(chartScreenshot)
    app.buttons["cash-flow-details"].tap()
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Housing"].firstMatch.waitForExistence(timeout: 10))
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.swipeDown()
    app.buttons["Previous cash flow month"].tap()
    XCTAssertTrue(app.staticTexts["January 2024"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testCashFlowEmptyState() {
    let app = launch("cash-flow-empty")
    app.buttons["Cash flow"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["No cash flow for this month."].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["cash-flow-details"].exists)
  }

  @MainActor
  func testCashFlowFailureCanRetry() {
    let app = launch("cash-flow-failure")
    app.buttons["Cash flow"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Retry cash flow"].waitForExistence(timeout: 10))
    app.buttons["Retry cash flow"].tap()
    XCTAssertTrue(app.buttons["cash-flow-details"].waitForExistence(timeout: 10))
  }

  @MainActor
  private func launch(_ scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SURE_SCENARIO"] = scenario
    app.launch()
    return app
  }
}
