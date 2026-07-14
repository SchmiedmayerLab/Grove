//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SpeziFoundation
import SpeziViews
public import SwiftUI


/// Displays the value of an `Bool`-based `AccountKey`.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct BoolDisplayView<Key: AccountKey>: DataDisplayView where Key.Value == Bool {
    public enum Label {
        case onOff
        case yesNo

        var onLabel: LocalizedStringResource {
            switch self {
            case .onOff:
                LocalizedStringResource("On", bundle: .atURL(from: .module))
            case .yesNo:
                LocalizedStringResource("YES", bundle: .atURL(from: .module))
            }
        }

        var offLabel: LocalizedStringResource {
            switch self {
            case .onOff:
                LocalizedStringResource("Off", bundle: .atURL(from: .module))
            case .yesNo:
                LocalizedStringResource("NO", bundle: .atURL(from: .module))
            }
        }
    }

    private let label: Label
    private let value: Key.Value

    public var body: some View {
        ListRow(Key.name) {
            if value {
                Text(label.onLabel)
            } else {
                Text(label.offLabel)
            }
        }
    }

    /// Create a new display view.
    /// - Parameters:
    ///   - label: The labels used to represent the `Bool` value.
    ///   - value: The value to display.
    public init(label: Label, _ value: Key.Value) {
        self.label = label
        self.value = value
    }

    /// Create a new display view.
    /// - Parameters:
    ///   - label: The labels used to represent the `Bool` value.
    ///   - keyPath: The `AccountKey` type.
    ///   - value: The value to display.
    @MainActor
    public init(label: Label = .onOff, _ keyPath: KeyPath<AccountKeys, Key.Type>, _ value: Key.Value) {
        self.init(label: label, value)
    }

    /// Create a new display view.
    /// - Parameter value: The value to display.
    public init(_ value: Key.Value) {
        self.init(label: .onOff, value)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountKey where Value == Bool {
    /// Default DataDisplay for `Bool`-based values.
    ///
    /// This represents the `Bool` using "On" and "Off" labels.
    public typealias DataDisplay = BoolDisplayView<Self>
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    List {
        BoolDisplayView<MockBoolKey>(true)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    List {
        BoolDisplayView<MockBoolKey>(false)
    }
}
#endif
