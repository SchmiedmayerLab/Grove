//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveBluetooth
import GroveFoundation
import OSLog

/// Manages and handles ongoing device connection attempts.
@available(iOS 18, macOS 15, watchOS 11, *)
struct DeviceConnections: Sendable {
    /// Retry configuration for a single connection.
    ///
    /// Implements a exponential backoff.
    struct RetryConfiguration {
        /// The initial backoff duration.
        var initialBackoff: Duration
        /// The maximum backoff duration.
        var maxBackoff: Duration
        /// The minimum period, if in which no error occurs, the error counter is reset.
        var minimumQuietPeriod: Duration

        /// The minimum time to wait after a regular disconnect, to reconnect to the device.
        var reconnectBackoff: Duration

        init(
            initialBackoff: Duration = .seconds(0.5),
            maxBackoff: Duration = .seconds(30),
            minimumQuietPeriod: Duration = .seconds(60),
            reconnectBackoff: Duration = .seconds(3)
        ) {
            self.initialBackoff = initialBackoff
            self.maxBackoff = maxBackoff
            self.minimumQuietPeriod = minimumQuietPeriod
            self.reconnectBackoff = reconnectBackoff
        }
    }

    private enum Input {
        case connect(_ device: PairedDevice, _ bluetooth: Bluetooth)
        case cancel(_ device: PairedDevice, disconnectPeripheral: (any PairableDevice)?)
        case clearStaleState(deviceId: UUID, identity: UUID)
    }

    private static let logger = Logger(subsystem: "org.grovealliance.devices", category: "\(Self.self)")

    private let input: (stream: AsyncStream<Input>, continuation: AsyncStream<Input>.Continuation)
    private let retry: RetryConfiguration

    init(retry: RetryConfiguration = RetryConfiguration()) {
        self.input = AsyncStream.makeStream()
        self.retry = retry
    }

    func connect(device: PairedDevice, using bluetooth: Bluetooth) {
        input.continuation.yield(.connect(device, bluetooth))
    }

    func cancel(device: PairedDevice, disconnect peripheral: (any PairableDevice)?) {
        input.continuation.yield(.cancel(device, disconnectPeripheral: peripheral))
    }

    func run() async {
        final class DeviceTaskHandle {
            let identity: UUID
            let handle: CancelableTaskHandle

            init(identity: UUID, handle: CancelableTaskHandle) {
                self.identity = identity
                self.handle = handle
            }
        }

        await withDiscardingTaskGroup { group in
            var state: [UUID: DeviceTaskHandle] = [:]

            for await input in self.input.stream {
                switch input {
                case let .connect(device, bluetooth):
                    guard state[device.id] == nil else {
                        Self.logger.warning("Ignoring connect request as task is still running.")
                        continue
                    }

                    let identity = UUID()

                    let handle = group.addCancelableTask {
                        await device.run(using: bluetooth, retry: self.retry)
                        self.input.continuation.yield(.clearStaleState(deviceId: device.id, identity: identity))
                    }

                    state[device.id] = DeviceTaskHandle(identity: identity, handle: handle)
                case let .cancel(device, peripheral):
                    let entry = state.removeValue(forKey: device.id)
                    entry?.handle.cancel()

                    if let peripheral {
                        await peripheral.disconnect()
                    }
                case let .clearStaleState(deviceId, identity):
                    guard let entry = state[deviceId],
                          entry.identity == identity else {
                        continue
                    }
                    state.removeValue(forKey: deviceId)
                }
            }
        }
    }
}
