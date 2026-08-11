//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveDevices
import GroveViews
import SwiftUI


struct DiscardButton: View {
    private let discard: () -> Void

    @Binding var viewState: ViewState
    
    
    var body: some View {
        Button(action: discard) {
            Text("Discard")
                .foregroundStyle(viewState == .idle ? Color.red : Color.gray)
        }
            .disabled(viewState != .idle)
    }

    init(viewState: Binding<ViewState>, discard: @escaping () -> Void) {
        self._viewState = viewState
        self.discard = discard
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
struct ConfirmMeasurementButton: View {
    private let confirm: @MainActor () async throws -> Void
    private let discard: () -> Void

    @ScaledMetric private var buttonHeight: CGFloat = 38
    @Binding var viewState: ViewState

    var body: some View {
        VStack {
            AsyncButton(state: $viewState, action: confirm) {
                Text("Save", bundle: .module)
                    .frame(maxWidth: .infinity, maxHeight: 35)
                    .font(.title2)
                    .bold()
            }
               .buttonStyle(.borderedProminent)
               .padding([.leading, .trailing], 36)

            DiscardButton(viewState: $viewState, discard: discard)
                .padding(.top, 8)
        }
    }

    init(viewState: Binding<ViewState>, confirm: @MainActor @escaping () async throws -> Void, discard: @escaping () -> Void) {
        self._viewState = viewState
        self.confirm = confirm
        self.discard = discard
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    ConfirmMeasurementButton(viewState: .constant(.idle)) {
        print("Save")
    } discard: {
        print("Discarded")
    }
}
#endif
