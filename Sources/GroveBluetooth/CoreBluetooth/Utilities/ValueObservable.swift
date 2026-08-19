//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


protocol AnyValueObservation {}


/// Internal value observation registrar.
///
/// Holds the registered closure till the next value update happens.
/// Inspired by Apple's Observation framework but with more power!
@available(iOS 18, macOS 15, watchOS 11, *)
final class ValueObservationRegistrar<Observable: ValueObservable>: Sendable {
    struct ValueObservation<Value>: AnyValueObservation {
        let handler: (Value) -> Void
    }

    @GroveBluetooth private var id: UInt64 = 0
    @GroveBluetooth private var observations: [UInt64: any AnyValueObservation] = [:]
    @GroveBluetooth private var keyPathIndex: [AnyKeyPath: Set<UInt64>] = [:]

    init() {}

    @GroveBluetooth
    private func nextId() -> UInt64 {
        defer {
            id &+= 1 // add with overflow operator
        }
        return id
    }

    @GroveBluetooth
    func onChange<Value>(of keyPath: KeyPath<Observable, Value>, perform closure: @escaping (Value) -> Void) {
        let id = nextId()
        observations[id] = ValueObservation(handler: closure)
        keyPathIndex[keyPath, default: []].insert(id)
    }

    @GroveBluetooth
    func triggerDidChange<Value>(for keyPath: KeyPath<Observable, Value>, on observable: Observable) {
        guard let ids = keyPathIndex.removeValue(forKey: keyPath) else {
            return
        }

        for id in ids {
            guard let anyObservation = observations.removeValue(forKey: id),
                  let observation = anyObservation as? ValueObservation<Value> else {
                continue
            }

            let value = observable[keyPath: keyPath]
            observation.handler(value)
        }
    }
}


/// A model with value observable properties.
@available(iOS 18, macOS 15, watchOS 11, *)
protocol ValueObservable: AnyObject, Sendable {
    // swiftlint:disable:next identifier_name
    var _$simpleRegistrar: ValueObservationRegistrar<Self> { get }

    @GroveBluetooth
    func onChange<Value>(of keyPath: KeyPath<Self, Value>, perform closure: @escaping (Value) -> Void)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ValueObservable {
    @GroveBluetooth
    func onChange<Value>(of keyPath: KeyPath<Self, Value>, perform closure: @escaping (Value) -> Void) {
        _$simpleRegistrar.onChange(of: keyPath, perform: closure)
    }
}
