//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// A section header that displays a title and an optional loading indicator.
///
/// This view is useful to, e.g., render the Section header of a list of nearby peripherals. The ProgressView can be used to
/// communicate that the application is currently scanning for nearby Bluetooth peripherals.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LoadingSectionHeader: View {
    private let text: Text
    private let loading: Bool

    public var body: some View {
        HStack {
            text
            if loading {
                ProgressView()
                    .padding(.leading, 4)
                    .accessibilityRemoveTraits(.updatesFrequently)
            }
        }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(text), Searching", bundle: .module))
    }

    @_disfavoredOverload
    public init(verbatim: String, loading: Bool) {
        self.init(Text(verbatim), loading: loading)
    }

    public init(_ title: LocalizedStringResource, loading: Bool) {
        self.init(Text(title), loading: loading)
    }


    public init(_ text: Text, loading: Bool) {
        self.text = text
        self.loading = loading
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    List {
        Section {
            Text(verbatim: "...")
        } header: {
            LoadingSectionHeader(verbatim: "Devices", loading: true)
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    LoadingSectionHeader(verbatim: "Devices", loading: true)
}
#endif
