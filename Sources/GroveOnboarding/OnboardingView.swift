//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveViews
public import SwiftUI


/// An onboarding step is a page.
///
/// ![An onboarding page with a title, information areas and a floating primary button.](Welcome)
///
/// The `OnboardingView` is GroveViews' `PageView`: a `PageHeader` and content that scroll, and `PageActions` floating
/// over them. Onboarding adds the ``OnboardingInformationView`` for the content and an initializer that composes the
/// three from a title, its areas and an action.
///
/// ```swift
/// OnboardingView(
///     title: "Title",
///     subtitle: "Subtitle",
///     areas: [
///         OnboardingInformationView.Area(
///             iconSymbol: "pc",
///             title: "PC",
///             description: "This is a PC."
///         ),
///         OnboardingInformationView.Area(
///             iconSymbol: "desktopcomputer",
///             title: "Mac",
///             description: "This is an iMac."
///         )
///     ],
///     actionText: "Continue"
/// ) {
///     // Action that should be performed upon tapping the "Continue" button ...
/// }
/// ```
///
/// - Tip: The ``SequentialOnboardingView`` shows information step by step instead.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias OnboardingView = PageView


@available(iOS 18, macOS 15, watchOS 11, *)
extension PageView where Header == PageHeader, Content == OnboardingInformationView, Footer == PageActions {
    /// Creates an onboarding step from a title, its information areas and a primary action.
    ///
    /// - Parameters:
    ///   - title: The step's localized title.
    ///   - subtitle: The step's optional localized subtitle.
    ///   - image: A symbol or picture shown large and tinted above the title.
    ///   - areas: The step's information areas, its main content.
    ///   - actionText: The localized text of the primary button.
    ///   - action: The closure that is called when the primary button is pressed.
    public init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        image: Image? = nil,
        areas: [OnboardingInformationView.Area],
        actionText: LocalizedStringResource,
        action: @escaping @MainActor () async throws -> Void
    ) {
        self.init {
            PageHeader(title: title, subtitle: subtitle, image: image)
        } content: {
            OnboardingInformationView(areas: areas)
        } footer: {
            PageActions(actionText) {
                try await action()
            }
        }
    }

    /// Creates an onboarding step from a title, its information areas and a primary action.
    ///
    /// - Parameters:
    ///   - title: The title without localization.
    ///   - subtitle: The subtitle without localization.
    ///   - image: A symbol or picture shown large and tinted above the title.
    ///   - areas: The step's information areas, its main content.
    ///   - actionText: The text of the primary button without localization.
    ///   - action: The closure that is called when the primary button is pressed.
    @_disfavoredOverload
    public init(
        title: some StringProtocol,
        subtitle: (some StringProtocol)? = String?.none,
        image: Image? = nil,
        areas: [OnboardingInformationView.Area],
        actionText: some StringProtocol,
        action: @escaping @MainActor () async throws -> Void
    ) {
        self.init {
            PageHeader(title: title, subtitle: subtitle, image: image)
        } content: {
            OnboardingInformationView(areas: areas)
        } footer: {
            PageActions(actionText) {
                try await action()
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    OnboardingView(
        title: String("Title"),
        subtitle: String("Subtitle"),
        areas: [
            OnboardingInformationView.Area(
                iconSymbol: "pc",
                title: String("PC"),
                description: String("This is a PC. And we can write a lot about PCs in a section like this. A very long text!")
            ),
            OnboardingInformationView.Area(
                iconSymbol: "desktopcomputer",
                title: String("Mac"),
                description: String("This is an iMac")
            ),
            OnboardingInformationView.Area(
                iconSymbol: "laptopcomputer",
                title: String("MacBook"),
                description: String("This is a MacBook")
            )
        ],
        actionText: String("Primary Button")
    ) {
        print("Primary!")
    }
}
#endif
