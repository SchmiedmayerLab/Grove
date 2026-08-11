//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveAccount
import GroveViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct FirebaseSignInWithAppleButton: View {
    @Environment(FirebaseAccountService.self)
    private var service

    // periphery:ignore - read through its projected value
    @State private var viewState: ViewState = .idle

    var body: some View {
        SignInWithAppleButton(state: $viewState) { request in
            service.onAppleSignInRequest(request: request)
        } onCompletion: { result in
            try await service.onAppleSignInCompletion(result: result)
        }
            .frame(height: 55)
            .viewStateAlert(state: $viewState)
    }

    nonisolated init() {}
}
