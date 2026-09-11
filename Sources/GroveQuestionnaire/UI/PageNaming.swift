//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


#if os(iOS)
/// The instrument's name under the page's, where the bar can show one: iOS 26; a macOS window names the page alone.
@available(iOS 18, *)
struct BarSubtitle: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        if #available(iOS 26, *), let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}
#endif


/// Names the page: in the navigation bar, inline, when a progress bar hangs off that bar, so nothing moves
/// between pages; otherwise on the page, rising into the bar as it scrolls.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PageNaming: ViewModifier {
    let title: String
    let subtitle: String?
    let inBar: Bool

    func body(content: Content) -> some View {
        if inBar {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(BarSubtitle(subtitle: subtitle))
                #endif
        } else {
            content.acceptsRisingTitle()
        }
    }
}


// MARK: Naming the Page
@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireSectionView {
    /// The page's name: the most specific short name the page was given, and the instrument's own name where
    /// it was given none.
    ///
    /// Only an authored `shortText` names a page. It was written for a display too narrow for the
    /// text it stands for, so it is the one thing a bar can cut without losing anything. Every
    /// authored `text` reaches the page instead. A group lends its name only when it is the only
    /// group on the page: a name in a bar has to describe everything under it, and with two
    /// groups neither one does.
    var pageTitle: String {
        switch context {
        case .regular(let questionnaire):
            let shortNames = [soleVisibleGroup?.shortTitle, section.shortTitle].compactMap { $0 }
            return shortNames.first { !$0.isEmpty } ?? questionnaire.metadata.title
        case .answerNestedQuestions(parentTask: _, let selectedOptionTitle, sections: _):
            return String(localized: "Follow-Up: \(selectedOptionTitle)", bundle: .module)
        }
    }

    /// The instrument's name, on a page named after one of its parts.
    var pageSubtitle: String? {
        guard case let .regular(questionnaire) = context, questionnaire.metadata.title != pageTitle else {
            return nil
        }
        return questionnaire.metadata.title
    }

    /// The group every rendered task belongs to, when they all share exactly one.
    private var soleVisibleGroup: Questionnaire.Task.Group? {
        var group: Questionnaire.Task.Group?
        for task in renderedTasks {
            guard let innermost = task.groupPath.last, innermost == (group ?? innermost) else {
                return nil
            }
            group = innermost
        }
        return group
    }
}
