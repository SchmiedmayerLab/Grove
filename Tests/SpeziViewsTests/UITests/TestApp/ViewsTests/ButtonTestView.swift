//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziViews
import SwiftUI


enum CustomError: Error, LocalizedError {
    case error

    var errorDescription: String? {
        "Custom Error"
    }

    var failureReason: String? {
        "Error was thrown!"
    }
}


struct StateAsyncButton: View {
    private let text: String

    @State private var presentedText: String?

    var body: some View {
        Section {
            AsyncButton("State Captured") {
                presentedText = text
            }
        } footer: {
            if let presentedText {
                Text("Captured \(presentedText)")
            }
        }
    }


    init(text: String) {
        self.text = text
    }
}


struct ButtonTestView: View {
    @State private var showCompleted = false
    @State private var viewState: ViewState = .idle

    @State private var showInfo = false
    @State private var presentedText = "Hello"

    var body: some View {
        Form { // swiftlint:disable:this closure_body_length
            if showCompleted {
                Section {
                    Text("Action executed")
                    Button("Reset") {
                        showCompleted = false
                    }
                }
            }
            Group {
                AsyncButton("Hello World") {
                    try? await Task.sleep(for: .milliseconds(500))
                    showCompleted = true
                }
                AsyncButton("Hello Throwing World", role: .destructive, state: $viewState) {
                    try await Task.sleep(for: .milliseconds(500))
                    throw CustomError.error
                }
                .asyncButtonProcessingStyle(.listRow)
            }
            .disabled(showCompleted)
            .viewStateAlert(state: $viewState)

            StateAsyncButton(text: presentedText)

            Section {
                HStack {
                    Button {
                        viewState = .error(CustomError.error)
                    } label: {
                        Text("Entity")
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    InfoButton("Entity Info") {
                        showCompleted = true
                    }
                }
            }
            
            Section {
                Button {
                    // not actually doing anything
                } label: {
                    Text("Tap Me ;)")
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyleGlass()
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section {
                Button {
                    // not actually doing anything
                } label: {
                    Text("Tap Me ;)")
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyleGlassProminent()
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            presentedText = "Hello World"
        }
        .toolbar {
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    AsyncButton(role: .confirm, state: $viewState) {
                        try await Task.sleep(for: .seconds(1))
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}


struct AsyncButtonDebounceTestView: View {
    @State private var fastCompleted = false
    @State private var slowCompleted = false
    @State private var fastViewState: ViewState = .idle
    @State private var slowViewState: ViewState = .idle

    var body: some View {
        Form {
            Section("Fast Action") {
                AsyncButton("Fast Debounced Action", state: $fastViewState) {
                    try await Task.sleep(for: .milliseconds(100))
                    fastCompleted = true
                }
                .asyncButtonProcessingStyle(.listRow)
                Text("Fast Completed: \(fastCompleted.description)")
            }

            Section("Slow Action") {
                AsyncButton("Slow Debounced Action", state: $slowViewState) {
                    try await Task.sleep(for: .seconds(5))
                    slowCompleted = true
                }
                .asyncButtonProcessingStyle(.listRow)
                Text("Slow Completed: \(slowCompleted.description)")
            }
        }
        .environment(\.processingDebounceDuration, .seconds(2))
    }
}


#if DEBUG
struct AsyncButtonTestView_Previews: PreviewProvider {
    static var previews: some View {
        ButtonTestView()
    }
}
#endif
