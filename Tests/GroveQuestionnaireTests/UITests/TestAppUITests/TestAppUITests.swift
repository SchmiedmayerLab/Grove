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

        var launchArguments: [String] {
            switch self {
            case .darkMode:
                []
            case .largestAccessibilityText:
                ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
        }

        @MainActor
        func applyToDevice() {
            switch self {
            case .darkMode:
                XCUIDevice.shared.appearance = .dark
            case .largestAccessibilityText:
                break
            }
        }
    }

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

    @MainActor
    func launchApp(_ conditions: LaunchCondition...) {
        app.launchArguments += conditions.flatMap(\.launchArguments)
        conditions.forEach { $0.applyToDevice() }
        XCTAssert(app.launchAndWait(for: app.buttons["Route:\(Route.swiftDSL.rawValue)"]))
    }

    /// Opens one of the authoring routes from the front page.
    @MainActor
    func open(_ route: Route) {
        tap(app.buttons["Route:\(route.rawValue)"])
        XCTAssert(app.navigationBars[route.rawValue].waitForExistence(timeout: 10))
    }

    /// Opens one of the renderer's own option pages from the front page.
    @MainActor
    func open(_ option: RendererOption) {
        tap(app.buttons["Renderer:\(option.rawValue)"])
        XCTAssert(app.navigationBars[option.rawValue].waitForExistence(timeout: 10))
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
        XCTAssert(app.buttons["StartQuestionnaire"].waitForExistence(timeout: 10))
    }

    /// Opens a FHIR row and starts the questionnaire from the resource's detail page.
    @MainActor
    func startFHIRExample(_ title: String, titled pageTitle: String? = nil) {
        openFHIRExample(title)
        tap(app.buttons["StartQuestionnaire"])
        waitForQuestionnaire(titled: pageTitle ?? title)
    }

    @MainActor
    func launchAppAndStartExample(_ title: String, in route: Route, titled pageTitle: String? = nil) {
        launchApp()
        open(route)
        startExample(title, titled: pageTitle)
    }

    @MainActor
    func launchAppAndStartFHIRExample(_ title: String, titled pageTitle: String? = nil) {
        launchApp()
        open(.fhir)
        startFHIRExample(title, titled: pageTitle)
    }

    /// Scrolls the enclosing list until the element can be tapped, then taps it.
    ///
    /// The attempt count is generous because an accessibility text size can stretch a page to
    /// several times its usual length, and eight swipes stopped short of the foot of one.
    @MainActor
    func tap(_ element: XCUIElement, scrollAttempts: Int = 20) {
        for _ in 0..<scrollAttempts where !element.isHittable {
            app.swipeUp()
        }
        XCTAssert(element.wait(for: \.isHittable, toEqual: true, timeout: 10))
        element.tap()
    }

    /// Walks back up to the front page, where the responses collected so far are listed.
    @MainActor
    func returnToRootPage() {
        let rootBar = app.navigationBars["Grove Questionnaire"]
        for _ in 0..<3 where !rootBar.exists {
            let backButton = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
            guard backButton.wait(for: \.isHittable, toEqual: true, timeout: 5) else {
                break
            }
            backButton.tap()
            _ = rootBar.waitForExistence(timeout: 2)
        }
        XCTAssert(rootBar.waitForExistence(timeout: 10))
    }

    /// Walks back to the front page and checks that `title` filed exactly one response there.
    @MainActor
    func assertResponseWasCollected(from title: String, count: Int = 1) {
        returnToRootPage()
        XCTAssert(app.staticTexts["Completed, \(count)"].waitForExistence(timeout: 10))
        XCTAssert(app.buttons["Response:\(title)"].exists)
    }

    @MainActor
    private func waitForQuestionnaire(titled title: String) {
        XCTAssert(questionnaire.waitUntilPresented())
        XCTAssert(questionnaire.waitUntilNavigationBarShows(title))
    }
}
