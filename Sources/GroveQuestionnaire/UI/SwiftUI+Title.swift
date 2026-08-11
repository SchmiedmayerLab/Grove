//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct ViewTitleConfig: Sendable {
    fileprivate let title: Text
    fileprivate let subtitle: Text?
    
    init(title: some StringProtocol, subtitle: (some StringProtocol)? = String?.none) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
    }
}


extension View {
    @ViewBuilder
    func navigationTitle(_ config: ViewTitleConfig?) -> some View {
        if let config {
            let withTitle = self.navigationTitle(config.title)
            if let subtitle = config.subtitle, #available(iOS 26, macOS 26, *) {
                withTitle.navigationSubtitle(subtitle)
            } else {
                withTitle
            }
        } else {
            self
        }
    }
}
