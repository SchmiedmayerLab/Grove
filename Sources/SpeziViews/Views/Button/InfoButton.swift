//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Icon-only info button.
///
/// You can use this button, e.g., on the trailing side of a list row to provide additional information about an entity.
public struct InfoButton: View {
    private let label: Text
    private let action: () -> Void

    public var body: some View {
        Button(action: action) {
            SwiftUI.Label {
                label
            } icon: {
                Image(systemName: "info.circle") // swiftlint:disable:this accessibility_label_for_image
            }
        }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundColor(.accentColor)
            .buttonStyle(.borderless) // ensure button is clickable next to the other button
            .accessibilityIdentifier("info-button")
            .accessibilityAction(named: label, action)
    }
    
    /// Create a new info button.
    /// - Parameters:
    ///   - label: The text label. This is not shown but useful for accessibility.
    ///   - action: The button action.
    public init(_ label: Text, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }
    
    /// Create a new info button.
    /// - Parameters:
    ///   - resource: The localized button label. This is not shown but useful for accessibility.
    ///   - action: The button action.
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    public init(_ resource: LocalizedStringResource, action: @escaping () -> Void) {
        self.label = Text(resource)
        self.action = action
    }
}


#if DEBUG
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
#Preview {
    List {
        Button {
            print("Primary")
        } label: {
            ListRow(verbatim: "Entry") {
                InfoButton(Text(verbatim: "Entry Info")) {
                    print("Info")
                }
            }
        }
    }
}
#endif
