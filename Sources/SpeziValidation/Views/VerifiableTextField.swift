//
// This source file is part of the Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// A `TextField` that automatically handles validation of input.
///
/// This text field expects a ``ValidationEngine`` object in the environment. The engine is used
/// to validate the text field input. A ``ValidationResultsView`` is used to automatically display
/// recovery suggestions for failed ``ValidationRule`` below the text field.
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
public struct VerifiableTextField<FieldLabel: View, FieldFooter: View>: View {
    /// The type of text field.
    public enum TextFieldType {
        /// A standard `TextField`.
        case text
        /// A `SecureField`.
        case secure
    }

    private let label: FieldLabel
    private let textFieldFooter: FieldFooter
    private let fieldType: TextFieldType

    @Binding private var text: String

    @Environment(ValidationEngine.self)
    var validationEngine: ValidationEngine?

    public var body: some View {
        VStack {
            Group {
                switch fieldType {
                case .text:
                    TextField(text: $text, label: { label })
                case .secure:
                    SecureField(text: $text, label: { label })
                }
            }

            HStack {
                if let validationEngine {
                    ValidationResultsView(results: validationEngine.displayedValidationResults)

                    Spacer()
                }

                textFieldFooter
            }
        }
    }


    /// Create a new verifiable text field.
    /// - Parameters:
    ///   - label: The localized text label for the text field.
    ///   - text: The binding to the stored value.
    ///   - type: An optional ``TextFieldType``.
    ///   - footer: An optional footer displayed below the text field next to the ``ValidationResultsView``.
    public init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        type: TextFieldType = .text,
        @ViewBuilder footer: () -> FieldFooter
    ) where FieldLabel == Text {
        self.init(text: text, type: type, label: { Text(label) }, footer: footer)
    }

    /// Create a new verifiable text field.
    /// - Parameters:
    ///   - label: The localized text label for the text field.
    ///   - text: The binding to the stored value.
    ///   - type: An optional ``TextFieldType``.
    public init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        type: TextFieldType = .text
    ) where FieldLabel == Text, FieldFooter == EmptyView {
        self.init(label, text: text, type: type, footer: EmptyView.init)
    }

    /// Create a new verifiable text field.
    /// - Parameters:
    ///   - text: The binding to the stored value.
    ///   - type: An optional ``TextFieldType``.
    ///   - label: An arbitrary label for the text field.
    ///   - footer: An optional footer displayed below the text field next to the ``ValidationResultsView``
    public init(
        text: Binding<String>,
        type: TextFieldType = .text,
        @ViewBuilder label: () -> FieldLabel,
        @ViewBuilder footer: () -> FieldFooter
    ) {
        self._text = text
        self.fieldType = type
        self.label = label()
        self.textFieldFooter = footer()
    }

    /// Create a new verifiable text field.
    /// - Parameters:
    ///   - text: The binding to the stored value.
    ///   - type: An optional ``TextFieldType``.
    ///   - label: An arbitrary label for the text field.
    public init(
        text: Binding<String>,
        type: TextFieldType = .text,
        @ViewBuilder label: () -> FieldLabel
    ) where FieldFooter == EmptyView {
        self.init(text: text, type: type, label: label, footer: EmptyView.init)
    }
}


#if DEBUG
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
#Preview {
    @Previewable @State var text = ""
    Form {
        VerifiableTextField(text: $text) {
            Text(verbatim: "Password Text")
        } footer: {
            Text(verbatim: "Some Hint")
                .font(.footnote)
        }
            .validate(input: text, rules: .nonEmpty)
    }
}
#endif
