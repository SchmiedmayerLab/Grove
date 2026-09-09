//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

@_spi(Experimental) import GroveHealthKit
import HealthKit
import Synchronization
import Testing


@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BackgroundObservationScopeTests {
    private enum Failure: Error { case expected }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func synchronousLaunchHookInstallsTheQueryBeforeReturning() async throws {
        let store = Store()
        let observation = store.startBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) { 42 }
        #expect(store.events == [.execute], "Installation must not wait for the returned task to be scheduled.")
        #expect(try await observation.value == 42)
        #expect(store.events == [.execute, .enable, .stop, .disable])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func cancellingImmediatelyStillStopsTheSynchronouslyInstalledQuery() async {
        let store = Store()
        let observation = store.startBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
            Issue.record("An already-cancelled observation must not enter its operation.")
        }
        observation.cancel()
        await #expect(throws: CancellationError.self) { try await observation.value }
        #expect(store.events == [.execute, .stop])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func cancelledLaunchCallerDoesNotInstallAQuery() async {
        let store = Store()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let observation: Task<Void, any Error> = store.startBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
                Issue.record("A cancelled launch caller must not start observation.")
            }
            try await observation.value
        }
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(store.events.isEmpty)
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func returnsTheBodyResultAfterStoppingAndReleasingDelivery() async throws {
        let store = Store()
        let result = try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
            #expect(store.events == [.execute, .enable])
            return 42
        }
        #expect(result == 42)
        #expect(store.events == [.execute, .enable, .stop, .disable])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func throwingBodyStillReleasesTheObservation() async {
        let store = Store()
        await #expect(throws: Failure.self) {
            try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
                throw Failure.expected
            }
        }
        #expect(store.events == [.execute, .enable, .stop, .disable])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func cancellationDuringRegistrationCleansUpWithoutEnteringTheBody() async throws {
        let store = Store(suspendEnable: true)
        let operation = Task {
            try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
                Issue.record("A cancelled registration must not enter the operation.")
            }
        }
        await store.waitForEnable()
        operation.cancel()
        store.finishEnable()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(store.events == [.execute, .enable, .stop, .disable])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test(arguments: [false, true])
    func cancellationInsideTheBodyCleansUpBeforeReturning(empty: Bool) async {
        let store = Store()
        let operation = Task {
            try await store.withBackgroundObservation(for: empty ? [] : [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(store.events == (empty ? [] : [.execute, .enable, .stop, .disable]))
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func registrationFailureStopsTheQueryWithoutEnteringTheBody() async {
        let store = Store(failEnable: true)
        await #expect(throws: Failure.self) {
            try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
                Issue.record("A failed registration must not enter the operation.")
            }
        }
        #expect(store.events == [.execute, .enable, .stop])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func emptyObservationDoesNotRegisterWithHealthKit() async throws {
        let store = Store()
        let value = try await store.withBackgroundObservation(for: [], updateHandler: { _ in }) { 42 }
        #expect(value == 42 && store.events.isEmpty)
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func nestedScopesKeepTheOuterBackgroundRegistration() async throws {
        let store = Store()
        try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
            try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {}
            #expect(store.events == [.execute, .enable, .execute, .enable, .stop])
        }
        #expect(store.events == [.execute, .enable, .execute, .enable, .stop, .stop, .disable])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func correlationCleanupReleasesTheExpandedQuantityTypes() async throws {
        let store = Store()
        try await store.withBackgroundObservation(for: [HKCorrelationType(.bloodPressure)], updateHandler: { _ in }) {}
        let expected: Set<HKObjectType> = [HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
        #expect(Set(store.enabledTypes) == expected)
        #expect(Set(store.disabledTypes) == expected)
        #expect(store.events == [.execute, .enable, .enable, .stop, .disable, .disable])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func cancelledBodyStillRetriesFailedDeliveryTeardown() async {
        let store = Store(disableFailures: 1)
        await #expect(throws: CancellationError.self) {
            try await store.withBackgroundObservation(for: [HKQuantityType(.heartRate)], updateHandler: { _ in }) {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        #expect(store.events == [.execute, .enable, .stop, .disable, .disable])
        #expect(store.disabledTypes == [HKQuantityType(.heartRate), HKQuantityType(.heartRate)])
    }

    @available(iOS 18, macOS 15, watchOS 11, *)
    @Test
    func cancelledPartialRegistrationStillRetriesRollback() async {
        let store = Store(suspendEnableAt: 2, disableFailures: 1)
        let operation = Task {
            try await store.withBackgroundObservation(for: [HKCorrelationType(.bloodPressure)], updateHandler: { _ in }) {
                Issue.record("Partial registration must not enter the operation.")
            }
        }
        await store.waitForEnable(count: 2)
        operation.cancel()
        store.finishEnable(success: false)
        await #expect(throws: Failure.self) { try await operation.value }
        #expect(store.events == [.execute, .enable, .enable, .disable, .disable, .stop])
        #expect(store.disabledTypes == Array(repeating: store.enabledTypes[0], count: 2))
    }
}


extension BackgroundObservationScopeTests {
    /// The SDK may invoke overrides on different queues. All mutable test state is protected by the mutex;
    /// the immutable stream is used only as a deterministic registration barrier.
    @available(iOS 18, macOS 15, watchOS 11, *)
    private final class Store: HKHealthStore, @unchecked Sendable {
        enum Event: Equatable { case execute, enable, stop, disable }
        private struct State {
            var events: [Event] = []
            var queries: [HKQuery] = []
            var enabledTypes: [HKObjectType] = []
            var disabledTypes: [HKObjectType] = []
            var enableCompletion: (@Sendable (Bool, (any Error)?) -> Void)?
            var disableFailures = 0
        }

        private let state = Mutex(State())
        private let enableStarted = AsyncStream<Void>.makeStream()
        private let suspendEnable: Bool
        private let failEnable: Bool
        private let suspendEnableAt: Int?

        var events: [Event] { state.withLock { $0.events } }
        var enabledTypes: [HKObjectType] { state.withLock { $0.enabledTypes } }
        var disabledTypes: [HKObjectType] { state.withLock { $0.disabledTypes } }

        init(suspendEnable: Bool = false, failEnable: Bool = false, suspendEnableAt: Int? = nil, disableFailures: Int = 0) {
            self.suspendEnable = suspendEnable
            self.failEnable = failEnable
            self.suspendEnableAt = suspendEnableAt
            super.init()
            state.withLock { $0.disableFailures = disableFailures }
        }

        override func execute(_ query: HKQuery) {
            state.withLock {
                $0.events.append(.execute)
                $0.queries.append(query)
            }
        }

        override func stop(_ query: HKQuery) {
            state.withLock {
                $0.events.append(.stop)
                $0.queries.removeAll { $0 === query }
            }
        }

        override func enableBackgroundDelivery(
            for type: HKObjectType,
            frequency: HKUpdateFrequency,
            withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void
        ) {
            let suspended = state.withLock {
                $0.events.append(.enable)
                $0.enabledTypes.append(type)
                let suspended = suspendEnable || $0.enabledTypes.count == suspendEnableAt
                if suspended { $0.enableCompletion = completion }
                return suspended
            }
            enableStarted.continuation.yield(())
            if !suspended { completion(!failEnable, failEnable ? Failure.expected : nil) }
        }

        override func disableBackgroundDelivery(
            for type: HKObjectType, withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void
        ) {
            let failed = state.withLock {
                $0.events.append(.disable)
                $0.disabledTypes.append(type)
                guard $0.disableFailures > 0 else {
                    return false
                }
                $0.disableFailures -= 1
                return true
            }
            completion(!failed, failed ? Failure.expected : nil)
        }

        func waitForEnable(count: Int = 1) async {
            var iterator = enableStarted.stream.makeAsyncIterator()
            for _ in 0..<count { _ = await iterator.next() }
        }

        func finishEnable(success: Bool = true) {
            let completion = state.withLock { state in
                defer { state.enableCompletion = nil }
                return state.enableCompletion
            }
            completion?(success, success ? nil : Failure.expected)
        }
    }
}

#endif
