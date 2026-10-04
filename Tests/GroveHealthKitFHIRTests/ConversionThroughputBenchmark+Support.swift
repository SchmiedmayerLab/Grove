//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The workloads, scopes and instruments of `ConversionThroughputBenchmark`; see that file for how to run it.
// swiftlint:disable force_try

#if canImport(HealthKit)

import CryptoKit
@preconcurrency import Darwin
import Foundation
import GroveFHIRContract
import GroveHealthKitFHIR
import HealthKit
import ModelsR4


enum BenchEnvironment {
    static let environment = ProcessInfo.processInfo.environment
    static let isEnabled = environment["GROVE_FHIR_BENCH_RUN"] == "1"
    static let sampleCount = environment["GROVE_FHIR_BENCH_N"].flatMap(Int.init) ?? 5_000
    static let runs = environment["GROVE_FHIR_BENCH_RUNS"].flatMap(Int.init) ?? 3
    static let only = environment["GROVE_FHIR_BENCH_ONLY"]
    static let outputPath = environment["GROVE_FHIR_BENCH_OUT"]
    static let dumpDirectory = environment["GROVE_FHIR_BENCH_DUMP"]
    /// "convert" or "graph-init": loop that phase for `profileSeconds` so an external profiler can attach.
    static let profile = environment["GROVE_FHIR_BENCH_PROFILE"]
    static let profileSeconds = environment["GROVE_FHIR_BENCH_PROFILE_SECONDS"].flatMap(Double.init) ?? 20
}


/// Collects result lines, prints them and optionally appends them to a file.
final class BenchReport {
    private var lines: [String] = []

    func line(_ text: String) {
        lines.append(text)
        print("BENCH \(text)")
    }

    func flush() {
        guard let path = BenchEnvironment.outputPath else {
            return
        }
        let text = lines.joined(separator: "\n") + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
        }
    }
}


enum Memory {
    /// The process's current and lifetime-peak physical footprint, in bytes.
    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (0, 0)
        }
        return (info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)))
    }

    static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}


enum Stopwatch {
    /// Seconds `body` took on the monotonic clock.
    static func seconds(_ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }
}


/// How one scenario's event contexts are configured.
enum ContextStyle: String {
    /// The suite's default fixture: logical subject, no study, every disclosure omitted.
    case minimal
    /// What MyHeartCounts configures: one study enrollment (three bundled study entries), the native
    /// HealthKit UUID disclosed under a deployment system, and a repository id on the Bundle.
    case deployment
}


struct Scenario {
    let name: String
    let style: ContextStyle
    let samples: [HKSample]
}


enum SampleFactory {
    static let start = Date(timeIntervalSince1970: 1_786_000_000)

    /// A watch as HealthKit reports it: named, but without a per-unit local identifier.
    static let watchWithoutUnitToken = HKDevice(
        name: "Apple Watch",
        manufacturer: "Apple Inc.",
        model: "Watch",
        hardwareVersion: "Watch7,5",
        firmwareVersion: nil,
        softwareVersion: "11.2",
        localIdentifier: nil,
        udiDeviceIdentifier: nil
    )

    /// A device that names a stable unit, so the graph carries a recording Device entry.
    static let deviceWithUnitToken = HKDevice(
        name: "Bench Sensor",
        manufacturer: "Example Devices",
        model: "Sensor One",
        hardwareVersion: "1.0",
        firmwareVersion: "2.0",
        softwareVersion: "3.0",
        localIdentifier: "bench-sensor-unit-0001",
        udiDeviceIdentifier: nil
    )

    static func heartRate(count: Int, device: HKDevice?, metadata: [String: Any]?) -> [HKSample] { // swiftlint:disable:this discouraged_optional_collection
        let unit = HKUnit.count().unitDivided(by: .minute())
        return (0..<count).map { index in
            let instant = start.addingTimeInterval(Double(index) * 5)
            return HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: unit, doubleValue: Double(55 + index % 90)),
                start: instant,
                end: instant,
                device: device,
                metadata: metadata
            )
        }
    }

    static func stepCount(count: Int) -> [HKSample] {
        (0..<count).map { index in
            let instant = start.addingTimeInterval(Double(index) * 60)
            return HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: Double(10 + index % 200)),
                start: instant,
                end: instant.addingTimeInterval(55),
                device: nil,
                metadata: nil
            )
        }
    }

    /// A one-hour run with a pause, a resume, eight laps and two generic segments; the converter withholds these events
    /// and exports the session only (the scenario keeps its name so runs stay comparable).
    static func workouts(count: Int, withEvents: Bool) -> [HKSample] {
        (0..<count).map { index in
            let begin = start.addingTimeInterval(Double(index) * 7_200)
            var events: [HKWorkoutEvent] = withEvents ? [
                HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: begin.addingTimeInterval(600), duration: 0), metadata: nil),
                HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: begin.addingTimeInterval(660), duration: 0), metadata: nil)
            ] : []
            for lap in 0..<(withEvents ? 8 : 0) {
                events.append(HKWorkoutEvent(
                    type: .lap,
                    dateInterval: DateInterval(start: begin.addingTimeInterval(Double(lap) * 400), duration: 400),
                    metadata: nil
                ))
            }
            for segment in 0..<(withEvents ? 2 : 0) {
                events.append(HKWorkoutEvent(
                    type: .segment,
                    dateInterval: DateInterval(start: begin.addingTimeInterval(Double(segment) * 1_800), duration: 1_800),
                    metadata: nil
                ))
            }
            return HKWorkout(
                activityType: .running,
                start: begin,
                end: begin.addingTimeInterval(3_600),
                workoutEvents: events.isEmpty ? nil : events,
                totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 640),
                totalDistance: HKQuantity(unit: .meter(), doubleValue: 10_000),
                metadata: [HKMetadataKeyTimeZone: "Europe/Berlin"]
            )
        }
    }
}


final class ManagedFailureCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}


/// The per-deployment facts a long-lived producer would hold once; only the event differs per sample.
struct BenchScope {
    static let producerInstance = UUID(uuid: (
        0x1f, 0x5c, 0x58, 0xaa, 0x6e, 0xc6, 0x4e, 0x79,
        0xa6, 0x82, 0x82, 0x9a, 0x9d, 0xeb, 0xd3, 0xf5
    ))
    static let nativeRecordSystem: IdentifierSystem = "https://bench.example.org/fhir/identifiers/healthkit-record"

    let systems: DeploymentIdentifierSystems
    let identityScope: OpaqueIdentityScope
    let repositoryScope: BusinessIdentifier
    let subject: Subject
    let application: ApplicationDevice
    let host: HostDevice
    let studies: [StudyEnrollment]

    init() {
        systems = try! DeploymentIdentifierSystems.derived(
            root: "https://bench.example.org/fhir",
            keyID: "store",
            epoch: EventSequence(1)
        )
        identityScope = try! OpaqueIdentityScope(
            systems: systems,
            keyID: "store",
            epoch: EventSequence(1),
            key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
        )
        repositoryScope = try! BusinessIdentifier(
            system: IdentifierSystem("https://bench.example.org/fhir/identifiers/repository"),
            value: "healthkit:participant-0001"
        )
        subject = .logical(try! BusinessIdentifier(
            system: IdentifierSystem("https://bench.example.org/fhir/identifiers/participant"),
            value: "participant-0001"
        ))
        application = try! ApplicationDevice(
            name: "Bench App",
            bundleIdentifier: "org.example.bench",
            version: "1.2.3",
            build: "456"
        )
        host = try! HostDevice(
            operatingSystemVersion: "26.1",
            name: "iPhone",
            manufacturer: "Apple Inc.",
            modelNumber: "iPhone17,1"
        )
        studies = [
            try! StudyEnrollment(
                study: BusinessIdentifier(
                    system: IdentifierSystem("https://bench.example.org/fhir/identifiers/research-study"),
                    value: "bench-study"
                ),
                protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://bench.example.org/fhir/PlanDefinition/bench-study")),
                protocolVersion: "7",
                enrollment: BusinessIdentifier(
                    system: IdentifierSystem("https://bench.example.org/fhir/identifiers/research-subject"),
                    value: "bench-study:participant-0001"
                )
            )
        ]
    }

    /// One sample's context under a distinct event sequence, the way a consumer builds it per record today.
    func context(for sample: HKSample, sequence: UInt64, style: ContextStyle) -> HealthKitConversionContext {
        let event = try! ExchangeEventIdentifier(
            system: systems.event,
            producerInstance: Self.producerInstance,
            sequence: EventSequence(sequence)
        )
        let instant = ExchangeEventContext.testInstant.addingTimeInterval(Double(sequence) / 1_000)
        switch style {
        case .minimal:
            return HealthKitConversionContext(
                event: ExchangeEventContext(
                    subject: subject,
                    event: event,
                    identityScope: identityScope,
                    repositoryScope: repositoryScope,
                    application: application,
                    host: host,
                    conversionInstant: instant
                )
            )
        case .deployment:
            return HealthKitConversionContext(
                event: ExchangeEventContext(
                    subject: subject,
                    event: event,
                    identityScope: identityScope,
                    repositoryScope: repositoryScope,
                    application: application,
                    host: host,
                    conversionInstant: instant,
                    studies: studies,
                    repositoryIDs: [.bundle: try! RepositoryID(sample.uuid.uuidString)]
                ),
                options: HealthKitConversionOptions(
                    nativeIdentifierDisclosure: .authorized(system: Self.nativeRecordSystem)
                )
            )
        }
    }
}

#endif
