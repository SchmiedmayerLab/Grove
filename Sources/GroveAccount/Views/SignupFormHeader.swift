//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
public struct SignupFormHeader: View {
    public var body: some View {
        PageHeader(
            title: .init("UP_SIGNUP_HEADER", bundle: .atURL(from: .module)),
            subtitle: .init("UP_SIGNUP_INSTRUCTIONS", bundle: .atURL(from: .module)),
            image: Image(systemName: "person.crop.circle.badge.plus") // swiftlint:disable:this accessibility_label_for_image
        )
    }

    public init() {}
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    SignupFormHeader()
}
#endif
