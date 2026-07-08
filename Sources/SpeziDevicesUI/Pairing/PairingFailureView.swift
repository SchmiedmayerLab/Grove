//
// This source file is part of the Stanford Spezi open-project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziDevices
import SwiftUI


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
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
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    SheetPreview {
        PairingFailureView(DevicePairingError.notInPairingMode)
    }
}
#endif
