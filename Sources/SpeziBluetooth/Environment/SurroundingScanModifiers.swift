//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
@Observable
final class SurroundingScanModifiers: EnvironmentKey, Sendable {
    static let defaultValue = SurroundingScanModifiers()

    @MainActor private var registeredModifiers: [AnyHashable: [UUID: any BluetoothScanningState]] = [:]

    init() {}

    @MainActor
    func setModifierScanningState<Scanner: BluetoothScanner>(enabled: Bool, with scanner: Scanner, modifierId: UUID, state: Scanner.ScanningState) {
        if enabled {
            registeredModifiers[AnyHashable(scanner.id), default: [:]]
                .updateValue(state, forKey: modifierId)
        } else {
            registeredModifiers[AnyHashable(scanner.id), default: [:]]
                .removeValue(forKey: modifierId)

            if registeredModifiers[AnyHashable(scanner.id)]?.isEmpty == true {
                registeredModifiers[AnyHashable(scanner.id)] = nil
            }
        }
    }

    @MainActor
    func retrieveReducedScanningState<Scanner: BluetoothScanner>(for scanner: Scanner) -> Scanner.ScanningState? {
        guard let entries = registeredModifiers[AnyHashable(scanner.id)] else {
            return nil
        }

        return entries.values
            .compactMap { anyState in
                anyState as? Scanner.ScanningState
            }
            .reduce(nil) { partialResult, state in
                guard let partialResult else {
                    return state
                }
                return partialResult.merging(with: state)
            }
    }

    @MainActor
    func hasPersistentInterest<Scanner: BluetoothScanner>(for scanner: Scanner) -> Bool {
        guard let ids = registeredModifiers[AnyHashable(scanner.id)] else {
            return false
        }
        return !ids.isEmpty
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension EnvironmentValues {
    var surroundingScanModifiers: SurroundingScanModifiers {
        get {
            self[SurroundingScanModifiers.self]
        }
        set {
            self[SurroundingScanModifiers.self] = newValue
        }
    }
}
