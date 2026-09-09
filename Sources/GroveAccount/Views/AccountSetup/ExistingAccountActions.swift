//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


/// The actions under an account that is already signed in: the app's way forward, and a way out.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ExistingAccountActions<Continue: View>: View {
    private let continueButton: Continue

    @Environment(Account.self)
    private var account

    // periphery:ignore - read through its projected value ($viewState)
    @State private var viewState: ViewState = .idle

    var body: some View {
        VStack(spacing: 12) {
            continueButton

            AsyncButton(role: .destructive, state: $viewState) {
                try await account.accountService.logout()
            } label: {
                Text("UP_LOGOUT", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.secondary)
            .controlSize(.large)
            .environment(\.defaultErrorDescription, .init("UP_LOGOUT_FAILED_DEFAULT_ERROR", bundle: .atURL(from: .module)))
        }
        .viewStateAlert(state: $viewState)
    }

    /// - Parameter continue: The app's own button to move on with the signed in account.
    init(@ViewBuilder `continue`: () -> Continue = { EmptyView() }) {
        self.continueButton = `continue`()
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    ExistingAccountActions {
        Button {
            print("Pressed")
        } label: {
            Text(verbatim: "Continue")
                .frame(maxWidth: .infinity)
        }
        .actionButtonStyle(.primary)
        .controlSize(.large)
    }
    .previewWith {
        AccountConfiguration(service: InMemoryAccountService())
    }
}
#endif
