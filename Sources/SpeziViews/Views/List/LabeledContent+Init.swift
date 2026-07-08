//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
extension LabeledContent where Label == Text, Content: View {
    /// Create a new list row with a localized text label.
    /// - Parameters:
    ///   - label: The localized text label.
    ///   - content: The content view.
    @_disfavoredOverload
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    public init(_ label: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.init(content: content) {
            Text(label)
        }
    }
}


@available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
extension LabeledContent where Label == Text, Content == Text {
    /// Creates a labeled informational view.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the view's localized title, that describes
    ///     the purpose of the view.
    ///   - value: The value being labeled.
    @_disfavoredOverload
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    public init<S: StringProtocol>(_ titleKey: LocalizedStringResource, value: S) {
        self.init {
            Text(value)
        } label: {
            Text(titleKey)
        }
    }
    
    /// Creates a labeled informational view from a formatted value.
    /// - Parameters:
    ///   - titleKey: A string that describes the purpose of the view.
    ///   - value: The value being labeled.
    ///   - format: A format style to convert the underlying value to a string representation.
    @_disfavoredOverload
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    public init<F: FormatStyle>(
        _ titleKey: LocalizedStringResource,
        value: F.FormatInput,
        format: F
    ) where F.FormatInput: Equatable, F.FormatOutput == String {
        self.init {
            Text(value, format: format)
        } label: {
            Text(titleKey)
        }
    }
}


#if DEBUG
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
#Preview { // swiftlint:disable:this closure_body_length
    List {
        LabeledContent(String("Hello")) {
            Text(verbatim: "World")
        }

        LabeledContent(String("Hello World")) {
            Text(verbatim: "There")
        }

        LabeledContent {
            Text(verbatim: "2")
        } label: {
            Text(verbatim: "Value")
            Text(verbatim: "The magic value")
        }

        HStack {
            LabeledContent(String("Device")) {
                EmptyView()
            }
            Spacer()
            ProgressView()
        }

        HStack {
            LabeledContent(String("Device")) {
                Text(verbatim: "World")
            }
            Spacer()
            ProgressView()
                .padding(.leading, 6)
        }

        HStack {
            LabeledContent(String("Long Device Name")) {
                Text(verbatim: "Long Description")
            }
            Spacer()
            ProgressView()
                .padding(.leading, 4)
        }
    }
}
#endif
