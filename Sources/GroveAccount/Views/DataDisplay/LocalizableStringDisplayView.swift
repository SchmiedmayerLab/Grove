//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation
import GroveViews
public import SwiftUI


/// Displays the value of an `CustomLocalizedStringResourceConvertible`-based `AccountKey`.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LocalizableStringDisplayView<Key: AccountKey>: DataDisplayView
    where Key.Value: CustomLocalizedStringResourceConvertible {
    private let value: Key.Value

    public var body: some View {
        ListRow(Key.name) {
            Text(value.localizedStringResource)
        }
    }

    /// Create a new display view.
    /// - Parameter value: The value to display.
    public init(_ value: Key.Value) {
        self.value = value
    }

    /// Create a new display view.
    /// - Parameters:
    ///   - keyPath: The `AccountKey` type.
    ///   - value: The value to display.
    @MainActor
    public init(_ keyPath: KeyPath<AccountKeys, Key.Type>, _ value: Key.Value) {
        self.init(value)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountKey where Value: CustomLocalizedStringResourceConvertible {
    /// Default DataDisplay for `CustomLocalizedStringResourceConvertible`-based values.
    public typealias DataDisplay = LocalizableStringDisplayView<Self>
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    Form {
        LocalizableStringDisplayView(\.genderIdentity, .preferNotToState)
    }
}
#endif
