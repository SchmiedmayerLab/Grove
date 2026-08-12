//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct EmptyServicesWarning: View {
    private var documentationUrl: URL {
        // we may move to a #URL macro once Swift 5.9 is shipping
        guard let docsUrl = URL(
            string: "https://github.com/SchmiedmayerLab/Grove/blob/main/Sources/GroveAccount/GroveAccount.docc/Setup-Guides/Initial-Setup.md"
        ) else {
            fatalError("Failed to construct GroveAccount Documentation URL. Please review URL syntax!")
        }
        return docsUrl
    }

    var body: some View {
        DocumentationInfoView(url: documentationUrl) {
            Label {
                Text("No Account Service", bundle: .module)
            } icon: {
                Image(systemName: "richtext.page")
                    .accessibilityHidden(true)
            }
        } description: {
            Text("MISSING_ACCOUNT_SERVICES", bundle: .module)
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    EmptyServicesWarning()
}
#endif
