//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveQuestionnaire


/// Getting around the catalog app. Everything inside a questionnaire belongs to ``questionnaire``.
///
/// Waits go through `waitUntil(timeout:_:)`: XCTest's own waits first look about a second in, even at
/// something already on screen, and a test here waits at nearly every step.
class TestAppUITests: XCTestCase, @unchecked Sendable {
    /// One of the three authoring routes listed on the catalog's front page.
    enum Route: String {
        case swiftDSL = "Swift DSL"
        case modelValues = "Model Values"
        case fhir = "FHIR JSON"
    }

    /// One of the renderer's own option pages, listed below the routes.
    enum RendererOption: String {
        case existingResponses = "Existing Responses"
        case completionFlow = "Completion Flow"
    }

    /// A display setting to launch under, for the pages whose layout or colours depend on one.
    ///
    /// Dark mode is a device setting rather than a launch argument: passing
    /// `-UIUserInterfaceStyle` leaves a SwiftUI app in whatever the device is already set to,
    /// which quietly photographs the light appearance twice. It outlives the process, so
    /// ``tearDown()`` puts it back.
    enum LaunchCondition {
        case darkMode
        case largestAccessibilityText
        /// Nothing animates, as on a host that has turned animations off.
        case animationsDisabled

        var launchArguments: [String] {
            switch self {
            case .darkMode:
                []
            case .animationsDisabled:
                ["--disableAnimations"]
            case .largestAccessibilityText:
                ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
        }

        @MainActor
        func applyToDevice() {
            switch self {
            case .darkMode:
                XCUIDevice.shared.appearance = .dark
            case .largestAccessibilityText, .animationsDisabled:
                break
            }
        }
    }

    /// How long a launch gets to come up, questionnaire included: a cold simulator can take its time.
    private static let launchTimeout: TimeInterval = 30

    @MainActor private(set) var app: XCUIApplication!

    /// The questionnaire the app currently has on screen.
    @MainActor private(set) var questionnaire: QuestionnaireSheetNavigator!

    /// The front page's count of everything answered so far.
    @MainActor var completedCount: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "CompletedCount").firstMatch
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        MainActor.assumeIsolated {
            app = XCUIApplication()
            questionnaire = QuestionnaireSheetNavigator(app)
            continueAfterFailure = false
        }
    }

    /// A test that fails before it can undo a device setting would hand it to every test after it,
    /// so the appearance goes back here, where no failure can skip it.
    override func tearDown() {
        MainActor.assumeIsolated {
            XCUIDevice.shared.appearance = .light
        }
        super.tearDown()
    }

    /// Launches onto the front page.
    @MainActor
    func launchApp(_ conditions: LaunchCondition...) {
        XCTAssert(launch(under: conditions, waitingFor: app.buttons["Route:\(Route.swiftDSL.rawValue)"]))
    }

    /// Launches the app, at `shortcut` when it names a place to start.
    ///
    /// `--start <page> [<example>]` has the app open the front-page entry titled `<page>` and start its
    /// example titled `<example>`: where tapping through would arrive, with nothing tapped. A test that is
    /// about a questionnaire spends its time on the questionnaire; ``BasicTests`` taps through by hand — a
    /// FHIR row and its resource, a catalog row, a renderer page — which keeps the taps working.
    @MainActor
    private func launch(
        under conditions: [LaunchCondition] = [],
        at shortcut: [String] = [],
        waitingFor element: XCUIElement? = nil
    ) -> Bool {
        if !shortcut.isEmpty {
            app.launchArguments += ["--start"] + shortcut
        }
        app.launchArguments += conditions.flatMap(\.launchArguments)
        conditions.forEach { $0.applyToDevice() }
        app.launch()
        return waitUntil(timeout: Self.launchTimeout) {
            app.state == .runningForeground && (element?.isHittable ?? true)
        }
    }

    /// Opens one of the authoring routes from the front page.
    @MainActor
    func open(_ route: Route) {
        tap(app.buttons["Route:\(route.rawValue)"])
        XCTAssert(waitUntil(timeout: 10) { app.navigationBars[route.rawValue].exists })
    }

    /// Opens one of the renderer's own option pages from the front page.
    @MainActor
    func open(_ option: RendererOption) {
        tap(app.buttons["Renderer:\(option.rawValue)"])
        XCTAssert(waitUntil(timeout: 10) { app.navigationBars[option.rawValue].exists })
    }

    /// Opens a catalog row, which presents its questionnaire straight away.
    ///
    /// - parameter pageTitle: The title the first page carries, when it differs from the row's.
    @MainActor
    func startExample(_ title: String, titled pageTitle: String? = nil) {
        tap(app.buttons["Example:\(title)"])
        waitForQuestionnaire(titled: pageTitle ?? title)
    }

    /// Opens a FHIR row, which leads to the resource before it leads to the renderer.
    @MainActor
    func openFHIRExample(_ title: String) {
        tap(app.buttons["Example:\(title)"])
        XCTAssert(waitUntil(timeout: 10) { app.buttons["StartQuestionnaire"].exists })
    }

    /// Opens a FHIR row and starts the questionnaire from the resource's detail page.
    @MainActor
    func startFHIRExample(_ title: String, titled pageTitle: String? = nil) {
        openFHIRExample(title)
        tap(app.buttons["StartQuestionnaire"])
        waitForQuestionnaire(titled: pageTitle ?? title)
    }

    /// Launches straight into an example of one of the authoring routes.
    ///
    /// - parameter pageTitle: The title the first page carries, when it differs from the row's.
    @MainActor
    func launchAppAndStartExample(_ title: String, in route: Route, titled pageTitle: String? = nil) {
        XCTAssert(launch(at: [route.rawValue, title]))
        waitForQuestionnaire(titled: pageTitle ?? title, timeout: Self.launchTimeout)
    }

    /// Launches straight into an example of one of the renderer's option pages.
    @MainActor
    func launchAppAndStartExample(_ title: String, in option: RendererOption, titled pageTitle: String? = nil) {
        XCTAssert(launch(at: [option.rawValue, title]))
        waitForQuestionnaire(titled: pageTitle ?? title, timeout: Self.launchTimeout)
    }

    /// Launches straight into a FHIR example, by way of the resource's detail page.
    @MainActor
    func launchAppAndStartFHIRExample(_ title: String, titled pageTitle: String? = nil, under conditions: [LaunchCondition] = []) {
        XCTAssert(launch(under: conditions, at: [Route.fhir.rawValue, title]))
        waitForQuestionnaire(titled: pageTitle ?? title, timeout: Self.launchTimeout)
    }

    /// Scrolls the enclosing list until the element can be tapped, then taps it.
    ///
    /// The attempt count is generous because an accessibility text size can stretch a page to
    /// several times its usual length, and eight swipes stopped short of the foot of one.
    @MainActor
    func tap(_ element: XCUIElement, scrollAttempts: Int = 20) {
        for _ in 0..<scrollAttempts {
            guard !element.isHittable else {
                break
            }
            app.swipeUp()
        }
        XCTAssert(waitUntil(timeout: 10) { element.isHittable })
        // An answer moves the page on a moment after its tap, and XCTest does not wait for that.
        element.waitUntilSettled(timeout: 2)
        element.tap()
    }

    /// Walks back up to the front page, where the responses collected so far are listed.
    @MainActor
    func returnToRootPage() {
        let rootBar = app.navigationBars["Grove Questionnaire"]
        for _ in 0..<3 {
            let backButton = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
            guard !rootBar.exists, waitUntil(timeout: 5, { backButton.isHittable }) else {
                break
            }
            backButton.tap()
            waitUntil(timeout: 2) { rootBar.exists }
        }
        XCTAssert(waitUntil(timeout: 10) { rootBar.exists })
    }

    /// Walks back to the front page and checks that `title` filed exactly one response there.
    @MainActor
    func assertResponseWasCollected(from title: String, count: Int = 1) {
        returnToRootPage()
        XCTAssert(waitUntil(timeout: 10) { app.staticTexts["Completed, \(count)"].exists })
        XCTAssert(app.buttons["Response:\(title)"].exists)
    }

    @MainActor
    private func waitForQuestionnaire(titled title: String, timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout) {
        XCTAssert(questionnaire.waitUntilPresented(timeout: timeout))
        XCTAssert(questionnaire.waitUntilTitled(title))
    }
}
