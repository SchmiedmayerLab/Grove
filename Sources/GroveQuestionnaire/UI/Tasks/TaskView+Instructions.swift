//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import MarkdownUI
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension TaskView {
    struct Instructions: View {
        let text: String
        
        var body: some View {
            if !text.isEmpty {
                Markdown(text)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
