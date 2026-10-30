//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveSensorKit
import Testing

@Suite("SensorKit device partitions")
struct DevicePartitionPlanTests {
    private struct Device: Equatable {
        let id: Int
        let productType: String
    }

    private enum ExpectedFailure: Error, Equatable {
        case ambiguous
        case fetch
    }

    @Test("Every device in a colliding partition is skipped while unique devices retain their order")
    func skipsOnlyAmbiguousPartitions() {
        let devices = [
            Device(id: 1, productType: "iPhone18,2"),
            Device(id: 2, productType: "Watch7,12"),
            Device(id: 3, productType: "iPhone18,2"),
            Device(id: 4, productType: "Watch7,11"),
            Device(id: 5, productType: "iPhone18,1"),
            Device(id: 6, productType: "iPhone18,1")
        ]
        let plan = DevicePartitionPlan(devices, productType: \.productType)

        #expect(plan.unambiguousDevices == [devices[1], devices[3]])
        #expect(plan.ambiguousProductTypes == ["iPhone18,1", "iPhone18,2"])
    }

    @Test("Unique batches are delivered before ambiguity is reported once")
    @available(iOS 18, macOS 15, watchOS 11, *)
    func failureFollowsUniqueBatches() async throws {
        var iterator = DevicePartitionIterator(
            base: [1, 2]._makeAsync().makeAsyncIterator(),
            failure: ExpectedFailure.ambiguous
        )

        #expect(try await iterator.next(isolation: nil) == 1)
        #expect(try await iterator.next(isolation: nil) == 2)
        await #expect(throws: ExpectedFailure.ambiguous) {
            try await iterator.next(isolation: nil)
        }
        #expect(try await iterator.next(isolation: nil) == nil)
    }

    @Test("No ambiguous devices means normal completion, including an empty device list", arguments: [[], ["Watch7,12"]])
    @available(iOS 18, macOS 15, watchOS 11, *)
    func uniquePartitionsComplete(_ devices: [String]) async throws {
        let plan = DevicePartitionPlan(devices, productType: \.self)
        #expect(plan.unambiguousDevices == devices)
        #expect(plan.ambiguousProductTypes.isEmpty)
        var iterator = DevicePartitionIterator(base: devices._makeAsync().makeAsyncIterator(), failure: nil)
        for device in devices {
            #expect(try await iterator.next(isolation: nil) == device)
        }
        #expect(try await iterator.next(isolation: nil) == nil)
    }

    @Test("An entirely ambiguous device list fails without yielding any batch")
    @available(iOS 18, macOS 15, watchOS 11, *)
    func allPartitionsAmbiguous() async {
        let plan = DevicePartitionPlan(["iPhone18,2", "iPhone18,2"], productType: \.self)
        var iterator = DevicePartitionIterator(
            base: plan.unambiguousDevices._makeAsync().makeAsyncIterator(),
            failure: ExpectedFailure.ambiguous
        )
        await #expect(throws: ExpectedFailure.ambiguous) {
            try await iterator.next(isolation: nil)
        }
    }

    @Test("An underlying fetch error is not replaced by the deferred ambiguity error")
    @available(iOS 18, macOS 15, watchOS 11, *)
    func underlyingFailureIsPreserved() async {
        let samples = AsyncThrowingStream<Int, any Error> { continuation in
            continuation.finish(throwing: ExpectedFailure.fetch)
        }
        var iterator = DevicePartitionIterator(base: samples.makeAsyncIterator(), failure: ExpectedFailure.ambiguous)
        await #expect(throws: ExpectedFailure.fetch) {
            try await iterator.next(isolation: nil)
        }
    }
}
