//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import SwiftUI


private enum AsyncButtonGroupResult {
    case debounce(showProcessing: Bool)
    case result(Result<Void, any Error>)
}


/// A SwiftUI `Button` that initiates an asynchronous (throwing) action.
///
/// The `AsyncButton` closely works together with the ``ViewState`` to control processing and error states.
///
/// Below is a short code example on how to use `ViewState` in conjunction with the `AsyncButton` to spin of a
/// async throwing action. It relies on the ``SwiftUICore/View/viewStateAlert(state:)-(Binding<ViewState>)`` modifier to present any
/// potential `LocalizedErrors` to the user.
///
/// ```swift
/// @State private var viewState: ViewState = .idle
///
/// var body: some View {
///     AsyncButton("Press Me", state: $viewState) {
///
///     }
///         .viewStateAlert(state: $viewState)
/// }
/// ```
///
/// - Important: The closure captures the state that was present at the moment the button was pressed. You might want to make sure you access state through Bindings if you want
///     to ensure that you always access the latest state possible.
///
/// ### Decouple Task Lifetime
///
/// A restriction of `AsyncButton` is that the task lifetime is bound to the appearance of the `Button` view. In certain cases (e.g., alert buttons or swipe action buttons), you might want to
/// continue running the task even if the button view disappears and bind the lifetime of the task to a view higher up the view hierarchy.
/// In these cases, you might want to use a pattern like the following and manage the lifetime yourself:
///
/// ```swift
/// struct MyView: View {
///     private enum Event {
///         case myEvent(String)
///     }
///
///     @State private var events: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation) = AsyncStream.makeStream()
///
///     var body: some View {
///         List(elements) { element in
///             Button("Remove") {
///                 events.continuation.yield(.myEvent(element))
///             }
///         }
///             .task {
///                 for await event in events.stream {
///                     // perform action and manage state
///                 }
///                 events = AsyncStream.makeStream() // durability over multiple appears
///             }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
public struct AsyncButton<Label: View>: View {
    private enum AsyncButtonState {
        case idle
        case disabled
        case disabledAndProcessing
    }

    private enum Event {
        case runAction(_ action: @MainActor () async throws -> Void)
    }

    private let role: ButtonRole?
    private let action: @MainActor () async throws -> Void
    private let label: Label?

    @Environment(\.defaultErrorDescription)
    private var defaultErrorDescription
    @Environment(\.processingDebounceDuration)
    private var processingDebounceDuration
    @Environment(\.asyncButtonProcessingStyle)
    private var processingStyle
    @Environment(\.isEnabled)
    private var isEnabled

    @State private var actionSignal: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation) = AsyncStream.makeStream()
    @State private var buttonState: AsyncButtonState = .idle
    @Binding private var viewState: ViewState

    // this covers the case where the encapsulating view sets the viewState binding to processing.
    // This should also make the button to rendered as processing!
    private var externallyProcessing: Bool {
        buttonState == .idle && viewState == .processing
    }

    private var isConsideredProcessing: Bool {
        buttonState == .disabledAndProcessing || externallyProcessing
    }

    private var consideredDisabled: Bool {
        !isEnabled || buttonState != .idle || externallyProcessing
    }

    public var body: some View {
        Group {
            if let label {
                customLabelButton(label)
            } else if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
                roleOnlyButton
            }
        }
        .disabled(consideredDisabled)
        .task {
            actionSignal = AsyncStream.makeStream() // durability over multiple appears
            for await event in actionSignal.stream {
                switch event {
                case let .runAction(closure):
                    await self.runAction(closure)
                }
            }
        }
    }

    @ViewBuilder
    private func customLabelButton(_ label: Label) -> some View {
        Button(role: role, action: submitAction) {
            switch processingStyle {
            case .overlay:
                label
                    .processingOverlay(isProcessing: isConsideredProcessing)
            case .listRow:
                ListRow {
                    label
                        .foregroundStyle(consideredDisabled ? .tertiary : .primary)
                } content: {
                    if isConsideredProcessing {
                        ProgressView()
                    }
                }
            }
        }
    }

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @ViewBuilder
    private var roleOnlyButton: some View {
        if let role {
            switch processingStyle {
            case .overlay:
                Button(role: role, action: submitAction)
                    .processingOverlay(isProcessing: isConsideredProcessing)
            case .listRow:
                Button(role: role, action: submitAction)
                    .foregroundStyle(consideredDisabled ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        if isConsideredProcessing {
                            ProgressView()
                        }
                    }
            }
        }
    }

    /// Creates an async button that generates its label from a provided localized string.
    /// - Parameters:
    ///   - title: The localized string used to generate the Label.
    ///   - role: An optional button role that is passed onto the underlying `Button`.
    ///   - action: An asynchronous button action.
    public init(
        _ title: LocalizedStringResource,
        role: ButtonRole? = nil,
        action: @MainActor @escaping () async -> Void
    ) where Label == Text {
        self.init(role: role, action: action) {
            Text(title)
        }
    }
    
    /// Creates an async button that generates its label from a provided without localization.
    /// - Parameters:
    ///   - title: The string used to generate the Label without localization.
    ///   - role: An optional button role that is passed onto the underlying `Button`.
    ///   - action: An asynchronous button action.
    @_disfavoredOverload
    public init<Title: StringProtocol>(
        _ title: Title,
        role: ButtonRole? = nil,
        action: @MainActor @escaping () async -> Void
    ) where Label == Text {
        self.init(role: role, action: action) {
            Text(verbatim: String(title))
        }
    }

    /// Creates an async button that displays a custom label.
    /// - Parameters:
    ///   - role: An optional button role that is passed onto the underlying `Button`.
    ///   - action: An asynchronous button action.
    ///   - label: The Button label.
    public init(
        role: ButtonRole? = nil,
        action: @MainActor @escaping () async -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
        self._viewState = .constant(.idle)
    }

    /// Creates an async throwing button that generates its label from a provided without localization.
    /// - Parameters:
    ///   - title: The string without localization used to generate the Label.
    ///   - role: An optional button role that is passed onto the underlying `Button`.
    ///   - state: A ``ViewState`` binding that it used to propagate any error caught in the button action.
    ///         It may also be used to externally control or observe the button's processing state.
    ///   - action: An asynchronous button action.
    @_disfavoredOverload
    public init<Title: StringProtocol>(
        _ title: Title,
        role: ButtonRole? = nil,
        state: Binding<ViewState>,
        action: @MainActor @escaping () async throws -> Void
    ) where Label == Text {
        self.init(role: role, state: state, action: action) {
            Text(verbatim: String(title))
        }
    }
    
    /// Creates an async throwing button that generates its label from a provided localized string.
    /// - Parameters:
    ///   - title: The localized string used to generate the Label.
    ///   - role: An optional button role that is passed onto the underlying `Button`.
    ///   - state: A ``ViewState`` binding that it used to propagate any error caught in the button action.
    ///         It may also be used to externally control or observe the button's processing state.
    ///   - action: An asynchronous button action.
    public init(
        _ title: LocalizedStringResource,
        role: ButtonRole? = nil,
        state: Binding<ViewState>,
        action: @MainActor @escaping () async throws -> Void
    ) where Label == Text {
        self.init(role: role, state: state, action: action) {
            Text(title)
        }
    }

    /// Creates an async button that displays a custom label.
    /// - Parameters:
    ///   - role: An optional button role that is passed onto the underlying `Button`.
    ///   - state: A ``ViewState`` binding that it used to propagate any error caught in the button action.
    ///         It may also be used to externally control or observe the button's processing state.
    ///   - action: An asynchronous button action.
    ///   - label: The Button label.
    public init(
        role: ButtonRole? = nil,
        state: Binding<ViewState>,
        action: @MainActor @escaping () async throws -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self._viewState = state
        self.action = action
        self.label = label()
    }

    /// Creates an async throwing button with a system-provided label for the supplied role.
    /// - Parameters:
    ///   - role: A button role that determines the system-provided label.
    ///   - state: A ``ViewState`` binding that is used to propagate any error caught in the button action.
    ///         It may also be used to externally control or observe the button's processing state.
    ///   - action: An asynchronous button action.
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public init(
        role: ButtonRole,
        state: Binding<ViewState>,
        action: @MainActor @escaping () async throws -> Void
    ) where Label == DefaultButtonLabel {
        self.role = role
        self._viewState = state
        self.action = action
        self.label = nil
    }

    private func submitAction() {
        guard buttonState == .idle else {
            return
        }
        buttonState = .disabled
        // we need to make sure that we pass in the latest closure with the latest captured view state.
        self.actionSignal.continuation.yield(.runAction(self.action))
    }

    private func runAction(_ action: @MainActor @escaping () async throws -> Void) async {
        guard buttonState == .disabled else {
            return
        }
        defer {
            buttonState = .idle
        }
        withAnimation(.easeOut(duration: 0.2)) {
            viewState = .processing
        }
        let result = await executeDebouncedAction(action)

        switch result {
        case .success:
            // the button action might set the state back to idle to prevent this animation
            if viewState != .idle {
                withAnimation(.easeIn(duration: 0.2)) {
                    viewState = .idle
                }
            }
        case let .failure(error):
            viewState = .error(AnyLocalizedError(
                error: error,
                defaultErrorDescription: defaultErrorDescription
            ))
        }
    }

    private func executeDebouncedAction(
        _ action: @MainActor @escaping () async throws -> Void
    ) async -> Result<Void, any Error> {
        let processingDebounceDuration = processingDebounceDuration
        return await withTaskGroup(of: AsyncButtonGroupResult.self) { group in
            group.addTask {
                try? await Task.sleep(for: processingDebounceDuration)
                // catching the case where the action runs a tiny bit faster than the debounce timer
                return .debounce(showProcessing: !Task.isCancelled)
            }
            group.addTask {
                do {
                    return .result(.success(try await action()))
                } catch {
                    return .result(.failure(error))
                }
            }
            guard let first = await group.next() else {
                fatalError("Unexpected TaskGroup state.")
            }
            if case .result = first {
                group.cancelAll() // cancel the debounce
            }
            if case .debounce(showProcessing: true) = first {
                withAnimation(.easeOut(duration: 0.2)) {
                    buttonState = .disabledAndProcessing
                }
            }
            guard let second = await group.next() else {
                fatalError("Unexpected TaskGroup state.")
            }
            switch (first, second) {
            case (let .result(result), .debounce), (.debounce, let .result(result)):
                return result
            case (.debounce, .debounce), (.result, .result):
                fatalError("TaskGroup inconsistency.")
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
private struct PreviewButton: View {
    var title: String = "Test Button"
    var role: ButtonRole?
    var duration: Duration = .seconds(1)
    var action: () async throws -> Void = {}
    @State var state: ViewState = .idle

    var body: some View {
        AsyncButton(title, role: role, state: $state) {
            try await Task.sleep(for: duration)
            try await action()
        }
        .viewStateAlert(state: $state)
        .buttonStyleGlassProminent()
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PreviewButton()
}
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PreviewButton(title: "Test Button with short action", duration: .milliseconds(100))
}
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PreviewButton(title: "Test Button with Error", duration: .seconds(0)) {
        throw CancellationError()
    }
}
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PreviewButton(title: "Processing only Button", state: .processing)
}
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PreviewButton(title: "Destructive Button", role: .destructive)
}
#endif
