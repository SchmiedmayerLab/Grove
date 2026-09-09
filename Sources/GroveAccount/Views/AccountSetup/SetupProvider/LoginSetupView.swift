//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveValidation
import GroveViews
import SwiftUI


private enum LoginFocusState {
    case userId
    case password
}


/// A default implementation for the embedded view of a ``UserIdPasswordAccountService``.
///
/// Every ``EmbeddableAccountService`` might provide a view that is directly integrated into the ``AccountSetup``
/// view for more easy navigation. This view implements such a view for ``UserIdPasswordAccountService``-based
/// account service implementations.
@available(iOS 18, macOS 15, watchOS 11, *)
struct LoginSetupView<PasswordReset: View>: View {
    private let loginClosure: (UserIdPasswordCredential) async throws -> Void
    private let passwordReset: PasswordReset
    private let supportsSignup: Bool

    @Binding private var presentingSignupSheet: Bool

    @Environment(Account.self)
    private var account

    @State private var userId: String = ""
    @State private var password: String = ""

    @State private var state: ViewState = .idle
    @FocusState private var focusedField: LoginFocusState?

    // for login we do all checks server-side. Except that we don't pass empty values.
    @ValidationState private var validation
    @State private var presentingPasswordForgetSheet = false

    @MainActor private var userIdConfiguration: UserIdConfiguration {
        account.accountService.configuration.userIdConfiguration
    }

    var body: some View {
        VStack(spacing: 16) {
            fields

            AsyncButton(state: $state, action: loginButtonAction) {
                Text("UP_LOGIN", bundle: .module)
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.primary)
            .controlSize(.large)
            .environment(\.defaultErrorDescription, .init("UP_LOGIN_FAILED_DEFAULT_ERROR", bundle: .atURL(from: .module)))


            if supportsSignup {
                Button(action: {
                    presentingSignupSheet = true
                }) {
                    Text("UP_SIGNUP_LINK", bundle: .module)
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .actionButtonStyle(.secondary)
                .controlSize(.large)
            }
        }
        .disableDismissiveActions(isProcessing: state)
        .viewStateAlert(state: $state)
        .receiveValidation(in: $validation)
        .sheet(isPresented: $presentingPasswordForgetSheet) {
            passwordReset
                .presentationBackground(.background)
        }
    }


    /// The two fields share a card, the way everything that asks for input does across Grove.
    @ViewBuilder @MainActor private var fields: some View {
        VStack(spacing: 0) { // swiftlint:disable:this closure_body_length
            Group {
                VerifiableTextField(userIdConfiguration.idType.localizedStringResource, text: $userId)
                    .validate(input: userId, rules: .nonEmpty)
                    .focused($focusedField, equals: .userId)
                    .textContentType(userIdConfiguration.textContentType)
#if !os(macOS) && !os(watchOS)
                    .keyboardType(userIdConfiguration.keyboardType)
#endif
                    .accountCardRow()

                Divider()

                VerifiableTextField(.init("UP_PASSWORD", bundle: .atURL(from: .module)), text: $password, type: .secure) {
                    if !(passwordReset is EmptyView) {
                        Button(action: {
                            presentingPasswordForgetSheet = true
                        }) {
                            Text("UP_FORGOT_PASSWORD", bundle: .module)
                                .font(.caption)
                                .bold()
#if os(macOS)
                                .foregroundColor(Color(nsColor: .systemGray))
#elseif os(watchOS)
                                .foregroundColor(Color(uiColor: .gray))
#else
                                .foregroundColor(Color(uiColor: .systemGray))
#endif
                        }
                    }
                }
                    .validate(input: password, rules: .nonEmpty)
                    .focused($focusedField, equals: .password)
                    .textContentType(.password)
                    .accountCardRow()
            }
                .environment(\.validationConfiguration, .hideFailedValidationOnEmptySubmit)
                .disableFieldAssistants()
                .textFieldStyle(.plain)
        }
            .accountCard()
    }


    init(
        loginClosure: @escaping (UserIdPasswordCredential) async throws -> Void,
        passwordReset: PasswordReset,
        supportsSignup: Bool,
        presentingSignup: Binding<Bool>
    ) {
        self.loginClosure = loginClosure
        self.passwordReset = passwordReset
        self.supportsSignup = supportsSignup
        self._presentingSignupSheet = presentingSignup
    }


    @MainActor
    private func loginButtonAction() async throws {
        guard validation.validateSubviews() else {
            return
        }

        focusedField = nil

        let credential = UserIdPasswordCredential(userId: userId, password: password)
        try await loginClosure(credential)
    }
}
