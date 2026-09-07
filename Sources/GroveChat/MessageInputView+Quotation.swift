//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 26, macOS 26, visionOS 26, *)
extension MessageInputView {
    /// The staged quotation, above the field, with a way to drop it before sending.
    @ViewBuilder var quotationPreview: some View {
        if let quotation {
            QuotationChip(text: quotation) {
                withAnimation(.smooth(duration: 0.25)) {
                    self.quotation = nil
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
