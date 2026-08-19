//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveDevices
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct PairingFailureView: View {
    private let error: any LocalizedError

    private var message: String {
        error.failureReason ?? error.errorDescription
            ?? String(localized: "Failed to pair accessory.", bundle: .module)
    }

    @Environment(\.dismiss)
    private var dismiss


    var body: some View {
        PaneContent(title: Text("Pairing Failed", bundle: .module), subtitle: Text(message)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
                .frame(maxWidth: 250, maxHeight: 120)
                .foregroundStyle(.red)
        } action: {
            Button {
                dismiss()
            } label: {
                Text("OK", bundle: .module)
                    .frame(maxWidth: .infinity, maxHeight: 35)
            }
                .buttonStyle(.borderedProminent)
                .padding([.leading, .trailing], 36)
        }
    }


    init(_ error: any LocalizedError) {
        self.error = error
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    SheetPreview {
        PairingFailureView(DevicePairingError.notInPairingMode)
    }
}
#endif
