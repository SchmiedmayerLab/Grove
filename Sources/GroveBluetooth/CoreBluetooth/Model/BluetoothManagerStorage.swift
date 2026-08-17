//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Atomics
import Foundation
import GroveFoundation
import OrderedCollections
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
final class BluetoothManagerStorage: ValueObservable, Sendable {
    private let _isScanning = ManagedAtomicMainActorBuffered<Bool>(false)
    private let _state = ManagedAtomicMainActorBuffered<BluetoothState>(.unknown)

    private let _discoveredPeripherals: MainActorBuffered<OrderedDictionary<UUID, BluetoothPeripheral>> = .init([:])
    private let lock = Mutex<Void>(())

    @GroveBluetooth var retrievedPeripherals: OrderedDictionary<UUID, WeakReference<BluetoothPeripheral>> = [:] {
        didSet {
            _$simpleRegistrar.triggerDidChange(for: \.retrievedPeripherals, on: self)
        }
    }
    @GroveBluetooth @ObservationIgnored private var subscribedContinuations: [UUID: AsyncStream<BluetoothState>.Continuation] = [:]
    @GroveBluetooth @ObservationIgnored private var subscribedEventHandlers: [UUID: (BluetoothState) -> Void] = [:]

    /// Note: we track, based on the CoreBluetooth reported connected state.
    @GroveBluetooth var connectedDevices: Set<UUID> = []
    @MainActor private(set) var maHasConnectedDevices: Bool = false // we need a main actor isolated one for efficient SwiftUI support.

    @GroveBluetooth var hasConnectedDevices: Bool {
        !connectedDevices.isEmpty
    }

    @inlinable var readOnlyState: BluetoothState {
        access(keyPath: \._state)
        return _state.load(ordering: .relaxed)
    }

    @inlinable var readOnlyIsScanning: Bool {
        access(keyPath: \._isScanning)
        return _isScanning.load(ordering: .relaxed)
    }

    @inlinable var readOnlyDiscoveredPeripherals: OrderedDictionary<UUID, BluetoothPeripheral> {
        access(keyPath: \._discoveredPeripherals)
        return _discoveredPeripherals.load(using: lock)
    }

    @GroveBluetooth var state: BluetoothState {
        get {
            readOnlyState
        }
        set {
            let didChange = _state.storeAndCompare(newValue) { @Sendable mutation in
                self.withMutation(keyPath: \._state, mutation)
            }

            if didChange {
                _$simpleRegistrar.triggerDidChange(for: \.state, on: self)
            }

            for continuation in subscribedContinuations.values {
                continuation.yield(state)
            }
            for handler in subscribedEventHandlers.values {
                handler(state)
            }
        }
    }

    @GroveBluetooth var isScanning: Bool {
        get {
            readOnlyIsScanning
        }
        set {
            let didChange = _isScanning.storeAndCompare(newValue) { @Sendable mutation in
                self.withMutation(keyPath: \._isScanning, mutation)
            }

            if didChange {
                _$simpleRegistrar.triggerDidChange(for: \.isScanning, on: self) // didSet
            }
        }
    }

    @GroveBluetooth var discoveredPeripherals: OrderedDictionary<UUID, BluetoothPeripheral> {
        get {
            readOnlyDiscoveredPeripherals
        }
        set {
            _discoveredPeripherals.store(newValue, using: lock) { @Sendable mutation in
                self.withMutation(keyPath: \._discoveredPeripherals, mutation)
            }

            _$simpleRegistrar.triggerDidChange(for: \.discoveredPeripherals, on: self) // didSet
        }
    }

    // swiftlint:disable:next identifier_name
    @ObservationIgnored let _$simpleRegistrar = ValueObservationRegistrar<BluetoothManagerStorage>()

    init() {}


    @GroveBluetooth
    func update(state: BluetoothState) {
        self.state = state
    }

    @GroveBluetooth
    func subscribe(_ continuation: AsyncStream<BluetoothState>.Continuation) -> UUID {
        let id = UUID()
        subscribedContinuations[id] = continuation
        return id
    }

    @GroveBluetooth
    func subscribe(_ handler: @escaping (BluetoothState) -> Void) -> StateRegistration {
        let id = UUID()
        subscribedEventHandlers[id] = handler
        return StateRegistration(id: id, storage: self)
    }

    @GroveBluetooth
    func unsubscribe(for id: UUID) {
        subscribedContinuations[id] = nil
        subscribedEventHandlers[id] = nil
    }

    @GroveBluetooth
    func cbDelegateSignal(connected: Bool, for id: UUID) {
        if connected {
            connectedDevices.insert(id)
        } else {
            connectedDevices.remove(id)
        }
        updateMainActorConnectedDevices(hasConnectedDevices: !connectedDevices.isEmpty)
    }

    private func updateMainActorConnectedDevices(hasConnectedDevices: Bool) {
        Task { @MainActor in
            maHasConnectedDevices = hasConnectedDevices
        }
    }


    deinit {
        Task { @GroveBluetooth [subscribedContinuations] in
            for continuation in subscribedContinuations.values {
                continuation.finish()
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BluetoothManagerStorage {
    var stateSubscription: AsyncStream<BluetoothState> {
        AsyncStream(BluetoothState.self) { continuation in
            Task { @GroveBluetooth [self] in
                let id = subscribe(continuation)
                continuation.onTermination = { @Sendable [weak self] _ in
                    guard let self = self else {
                        return
                    }
                    Task.detached { @Sendable @GroveBluetooth in
                        self.unsubscribe(for: id)
                    }
                }
            }
        }
    }
}
