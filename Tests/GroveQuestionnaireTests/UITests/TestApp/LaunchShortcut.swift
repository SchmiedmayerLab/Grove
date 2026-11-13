//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// An entry on the front page that leads to a page of its own.
enum CatalogPage: Hashable {
    case route(AuthoringRoute)
    case existingResponses
    case completionFlow

    static let allCases: [Self] = AuthoringRoute.allCases.map(Self.route) + [.existingResponses, .completionFlow]

    var title: String {
        switch self {
        case .route(let route): route.title
        case .existingResponses: "Existing Responses"
        case .completionFlow: "Completion Flow"
        }
    }
}


/// Where a UI test asked the app to open, so that a test about a questionnaire spends its time on the
/// questionnaire rather than on the catalog in front of it.
///
/// `--start <page> [<example>]` opens the front-page entry titled `<page>` and starts its example titled
/// `<example>`, as tapping through would. Getting there by hand is the contract test's job; every other
/// test only needs to arrive.
@MainActor
enum LaunchShortcut {
    /// The front-page entry the app opens at launch.
    static let page: CatalogPage? = argument(at: 1).flatMap { title in
        CatalogPage.allCases.first { $0.title == title }
    }

    /// The example still waiting to be started.
    private static var example: String? = argument(at: 2)

    /// Whether `title` is the example waiting to be started, without starting it.
    static func isWaiting(_ title: String) -> Bool {
        example == title
    }

    /// Whether `title` is the example waiting to be started, which it no longer is afterwards: a page
    /// visited again later starts nothing.
    static func claim(_ title: String) -> Bool {
        guard isWaiting(title) else {
            return false
        }
        example = nil
        return true
    }

    /// The value `offset` places after `--start`, if the launch carries one.
    private static func argument(at offset: Int) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--start"), arguments.indices.contains(flag + offset) else {
            return nil
        }
        let value = arguments[flag + offset]
        return value.hasPrefix("-") ? nil : value
    }
}
