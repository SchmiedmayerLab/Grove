//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import AuthenticationServices
import Foundation
import Grove
public import GroveViews
public import SwiftUI


/// Create a Sign in with Apple button with Grove Account support.
///
/// This view augments the [`SignInWithAppleButton`](https://developer.apple.com/documentation/authenticationservices/signinwithapplebutton)
/// with additional support for `GroveAccount`-related functionality. For example, it automatically controls the
/// [`Label`](https://developer.apple.com/documentation/authenticationservices/signinwithapplebutton/label)
/// based on the ``PreferredSetupStyle``. Further it automatically reports the ``SignupProviderCompliance`` based on the request scopes.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct SignInWithAppleButton: View {
    private let overrideLabel: AuthenticationServices.SignInWithAppleButton.Label?
    private let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    private let onCompletion: (Result<ASAuthorization, any Error>) async throws -> Void

    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.defaultErrorDescription)
    private var defaultErrorDescription
    @Environment(\.preferredSetupStyle)
    private var preferredSetupStyle

    @State private var compliance: SignupProviderCompliance?
    @State private var lastRequestScopes: [ASAuthorization.Scope]? // swiftlint:disable:this discouraged_optional_collection
    @State private var lastTask: Task<Void, Never>? {
        willSet {
            lastTask?.cancel()
        }
    }

    @Binding private var viewState: ViewState

    private var label: AuthenticationServices.SignInWithAppleButton.Label {
        if let overrideLabel {
            return overrideLabel
        }

        switch preferredSetupStyle {
        case .automatic, .login:
            return .signIn
        case .signup:
            return .signUp
        }
    }

    public var body: some View {
        AuthenticationServices.SignInWithAppleButton(label) { request in
            onRequest(request)
            lastRequestScopes = request.requestedScopes
        } onCompletion: { result in
            if case .success = result {
                if lastRequestScopes?.contains(.fullName) == true {
                    compliance = .askedFor {
                        \.name
                    }
                } else {
                    compliance = .askedFor(keys: [])
                }
            }

            lastTask = Task {
                do {
                    try await onCompletion(result)
                } catch {
                    compliance = nil

                    if let localizedError = error as? any LocalizedError {
                        viewState = .error(localizedError)
                    } else {
                        viewState = .error(AnyLocalizedError(
                            error: error,
                            defaultErrorDescription: defaultErrorDescription
                        ))
                    }
                }

                lastTask = nil
            }
        }
            .onDisappear {
                lastTask?.cancel()
            }
            .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
            .reportSignupProviderCompliance(compliance)
    }

    /// Create a new Sign in with Apple button.
    /// - Parameters:
    ///   - label: Optionally override the label that is used for the button. Otherwise, it will be derived from the ``PreferredSetupStyle``.
    ///   - onRequest: The authorization request for an Apple ID.
    ///   - onCompletion: The completion handler that the system calls when the sign-in completes.
    public init(
        _ label: AuthenticationServices.SignInWithAppleButton.Label? = nil,
        onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
        onCompletion: @escaping ((Result<ASAuthorization, any Error>) async -> Void)
    ) {
        self.init(label, state: .constant(.idle), onRequest: onRequest, onCompletion: onCompletion)
    }

    /// Create a new Sign in with Apple button.
    /// - Parameters:
    ///   - label: Optionally override the label that is used for the button. Otherwise, it will be derived from the ``PreferredSetupStyle``.
    ///   - state: A view state binding that is used to set the error state if the `onCompletion` handler returns an error.
    ///   - onRequest: The authorization request for an Apple ID.
    ///   - onCompletion: The completion handler that the system calls when the sign-in completes.
    public init(
        _ label: AuthenticationServices.SignInWithAppleButton.Label? = nil,
        state: Binding<ViewState>,
        onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
        onCompletion: @escaping ((Result<ASAuthorization, any Error>) async throws -> Void)
    ) {
        self.overrideLabel = label
        self._viewState = state
        self.onRequest = onRequest
        self.onCompletion = onCompletion
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    SignInWithAppleButton { request in
        request.requestedScopes = [.email, .fullName]
        request.nonce = "ASDF"
    } onCompletion: { result in
        print("Result \(result)")
    }
}
#endif
