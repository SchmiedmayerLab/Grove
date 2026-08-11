//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation
import GroveValidation
public import SwiftUI


/// Entry or modify the value of an `String`-based `AccountKey`.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct StringEntryView<Key: AccountKey>: DataEntryView where Key.Value == String {
    @Binding private var value: String

    public var body: some View {
        VerifiableTextField(Key.name, text: $value)
            .disableAutocorrection(true)
    }


    /// Create a new entry view.
    /// - Parameter value: The binding to the value to modify.
    public init(_ value: Binding<String>) {
        _value = value
    }

    // periphery:ignore:parameters keyPath - binds the generic Key at the call site
    /// Create a new entry view.
    /// - Parameters:
    ///   - keyPath: The `AccountKey` type.
    ///   - value: The binding to the value to modify.
    @MainActor
    public init(_ keyPath: KeyPath<AccountKeys, Key.Type>, _ value: Binding<Key.Value>) {
        self.init(value)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountKey where Value == String {
    /// Default DataEntry for `String`-based values.
    public typealias DataEntry = StringEntryView<Self>
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @Previewable @State var value = "Hello World"
    List {
        StringEntryView(\.userId, $value)
            .validate(input: value, rules: .nonEmpty)
    }
}
#endif
