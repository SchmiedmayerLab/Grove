//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveValidation
import GroveViews
public import SwiftUI


/// A password reset view implementation.
///
/// You can use this view to implement a basic password reset operation.
///
/// - Tip: You can throw an `LocalizedError` to communicate erroneous conditions back to the user.
///
/// Below is a short code example on how to use this view.
/// ```swift
/// struct MyView: View {
///     var body: some View {
///         PasswordResetView { userId in
///             // handle password reset for the requested user id
///         }
///     }
/// }
/// ```
///
/// - Note: Use ``init(resetPassword:success:)`` to provide a custom view that appears for a successful password reset.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct PasswordResetView<SuccessView: View>: View {
    private let successView: SuccessView
    private let resetPasswordClosure: (String) async throws -> Void

    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss

    @ValidationState private var validation

    @State private var userId = ""
    @State private var didReset: Bool

    @State private var state: ViewState = .idle
    @FocusState private var isFocused: Bool

    private var userIdConfiguration: UserIdConfiguration {
        account.accountService.configuration.userIdConfiguration
    }


    public var body: some View {
        Group {
            if didReset {
                PageView {
                    successView
                }
            } else {
                PageView {
                    PageHeader(
                        title: String(localized: "UP_RESET_PASSWORD", bundle: .module),
                        subtitle: String(localized: "UAP_PASSWORD_RESET_SUBTITLE \(userIdConfiguration.idType.localizedStringResource)", bundle: .module),
                        image: Image(systemName: "person.badge.key") // swiftlint:disable:this accessibility_label_for_image
                    )
                } content: {
                    userIdField
                        .accountCardRow()
                        .accountCard()
                } footer: {
                    AsyncButton(state: $state, action: submitRequestAction) {
                        Text("UP_RESET_PASSWORD", bundle: .module)
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .actionButtonStyle(.primary)
                    .controlSize(.large)
                }
            }
        }
        .disableDismissiveActions(isProcessing: state)
        .receiveValidation(in: $validation)
        .viewStateAlert(state: $state)
        .environment(\.defaultErrorDescription, .init("UAP_RESET_PASSWORD_FAILED_DEFAULT_ERROR", bundle: .atURL(from: .module)))
        .toolbar {
            ToolbarItem(placement: didReset ? .confirmationAction : .cancellationAction) {
                if #available(iOS 26.0, macCatalyst 26.0, visionOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, *) {
                    Button(role: didReset ? .confirm : .cancel) {
                        dismiss()
                    }
                    .disabled(state == .processing)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text(didReset ? "Done" : "Cancel", bundle: .module)
                    }
                    .disabled(state == .processing)
                }
            }
        }
    }

    @MainActor private var userIdField: some View {
        VerifiableTextField(userIdConfiguration.idType.localizedStringResource, text: $userId)
            .validate(input: userId, rules: .nonEmpty)
            .focused($isFocused)
            .disableFieldAssistants()
            .textContentType(userIdConfiguration.textContentType)
#if !os(macOS) && !os(watchOS)
            .keyboardType(userIdConfiguration.keyboardType)
#endif
    }

    fileprivate init(
        didReset: Bool,
        resetPassword: @escaping (String) async throws -> Void,
        @ViewBuilder success successViewBuilder: () -> SuccessView = { SuccessfulPasswordResetView() }
    ) {
        self.resetPasswordClosure = resetPassword
        self.successView = successViewBuilder()
        self._didReset = State(wrappedValue: didReset)
    }


    /// Create a new view.
    /// - Parameters:
    ///   - resetPassword: A closure that is executed when the user request to reset their password. The closure receives the ``AccountDetails/userId`` as an argument.
    ///   - success: A view to display on successful password reset.
    public init(
        resetPassword: @escaping (String) async throws -> Void,
        @ViewBuilder success: @escaping () -> SuccessView = { SuccessfulPasswordResetView() }
    ) {
        self.init(didReset: false, resetPassword: resetPassword, success: success)
    }


    @MainActor
    private func submitRequestAction() async throws {
        guard validation.validateSubviews() else {
            return
        }

        isFocused = false

        let userId = userId
        try await resetPasswordClosure(userId)

        withAnimation(.easeOut(duration: 0.5)) {
            didReset = true
        }

        Task {
            // Keep the reset delay independent of the task owned by this view.
            try? await Task.sleep(for: .milliseconds(515))
            state = .idle
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    NavigationStack {
        PasswordResetView { userId in
            print("Reset password for \(userId)")
        }
        .previewWith {
            AccountConfiguration(service: InMemoryAccountService())
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    NavigationStack {
        PasswordResetView(didReset: true) { userId in
            print("Reset password for \(userId)")
        }
        .previewWith {
            AccountConfiguration(service: InMemoryAccountService())
        }
    }
}
#endif
