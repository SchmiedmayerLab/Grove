//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Baseline-throughput benchmark of the HealthKit -> FHIR converter. It never runs in a normal test run:
// the suite is enabled only when GROVE_FHIR_BENCH_RUN=1 reaches the test process.
//
// Running it in RELEASE mode, which is the only configuration whose numbers mean anything:
//
//   (1) Through Xcode on the plain checkout, with the shared build cache (`xcodebuild` forwards only
//       TEST_RUNNER_-prefixed variables into the test process; Release needs testability for @testable, and
//       matches the macOS destination only without an `arch=` qualifier). Verified on 2026-10-03:
//
//         cd <checkout> && GROVE_LOWERED_DEPLOYMENT_TARGETS=0 GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS=1 \
//           GROVE_EXCLUDE_DOCC_CATALOGS=1 \
//           TEST_RUNNER_GROVE_FHIR_BENCH_RUN=1 TEST_RUNNER_GROVE_FHIR_BENCH_N=5000 TEST_RUNNER_GROVE_FHIR_BENCH_RUNS=3 \
//           TEST_RUNNER_GROVE_FHIR_BENCH_OUT=/tmp/bench-results.txt \
//           xcodebuild test -scheme Grove-Tests -testPlan GroveHealthKitFHIR \
//             -only-testing:GroveHealthKitFHIRTests/ConversionThroughputBenchmark \
//             -configuration Release ENABLE_TESTABILITY=YES ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=26.0 \
//             -destination 'platform=macOS' -derivedDataPath "$PWD/.derivedData" -packageCachePath "$PWD/.packageCache" \
//             -skipMacroValidation -skipPackagePluginValidation 2>&1 | grep '^BENCH\|error:'
//
//   (2) Through SwiftPM in a scratch build directory outside the checkout. `swift test` builds every test
//       target of the monorepo, so this route is practical only with a manifest that shrinks the graph to this
//       test target's closure. The checked-in manifest has no such switch; the first measurements used a scratch
//       copy whose GROVE_FHIR_BENCH=1 block did that. With such a manifest:
//
//         cd <checkout> && GROVE_FHIR_BENCH=1 GROVE_EXCLUDE_DOCC_CATALOGS=1 GROVE_FHIR_BENCH_RUN=1 \
//           xcrun swift test -c release -Xswiftc -enable-testing --scratch-path <scratch-build-dir> \
//             --filter ConversionThroughputBenchmark
//
//       Use `xcrun swift`, never a bare `swift`: a swiftly-managed toolchain cannot load this manifest against
//       the current SDK. A tree that predates ExchangeGraph.ValidationDocument needs `-Xswiftc -DGROVE_BENCH_NO_PASS_TIMING`.
//
// Environment (plain names under SwiftPM, TEST_RUNNER_-prefixed under xcodebuild):
//   GROVE_FHIR_BENCH_RUN=1        enable
//   GROVE_FHIR_BENCH_N=5000       samples per quantity scenario (workouts use N/10, at least 100)
//   GROVE_FHIR_BENCH_RUNS=3       timed repetitions of the convert() loop
//   GROVE_FHIR_BENCH_ONLY=name    run only the scenario with this name ("concurrent", or "workout-diagnose")
//   GROVE_FHIR_BENCH_OUT=path     also append the result lines to this file
//   GROVE_FHIR_BENCH_DUMP=dir     write each scenario's first Bundle JSON there and report per-entry sizes
//   GROVE_FHIR_BENCH_PROFILE=convert|graph-init   loop one phase (deployment heart rate) for an external profiler
//   GROVE_FHIR_BENCH_PROFILE_SECONDS=20           how long that loop runs
//
// The scenario names (heartRate-minimal, heartRate-deployment-watch, heartRate-deployment-recordingDevice,
// stepCount-minimal, stepCount-deployment, workout-noEvents-deployment, workout12segments-deployment,
// concurrent-heartRate-deployment-watch) and the result-line format are fixed so runs stay comparable.
// swiftlint:disable force_unwrapping

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The measured state of one scenario, carried from phase to phase.
private struct ScenarioRun {
    let scenario: Scenario
    let scope: BenchScope
    let report: BenchReport
    let converter = HealthKitConverter()
    var contexts: [HealthKitConversionContext] = []
    var conversions: [HealthKitConversionSet] = []
    var encoded: [Data] = []
    var bestConvertSeconds = 0.0
    var encodeSeconds = 0.0
    var graphInitSeconds = 0.0

    var samples: [HKSample] { scenario.samples }
    var count: Int { scenario.samples.count }
    var name: String { scenario.name }

    func rate(_ seconds: Double, _ items: Int? = nil) -> String {
        let items = Double(items ?? count)
        return String(format: "%.3fs %.1f/s %.1fus/sample", seconds, items / seconds, seconds / items * 1_000_000)
    }

    func convert(_ index: Int) throws -> HealthKitConversionSet {
        try autoreleasepool { try converter.convert(samples[index], context: contexts[index]) }
    }
}


@Suite(.serialized, .enabled(if: BenchEnvironment.isEnabled))
struct ConversionThroughputBenchmark {
    private static let warmUpCount = 200

    private static func scenarios(count: Int) -> [Scenario] {
        [
            Scenario(name: "heartRate-minimal", style: .minimal, samples: SampleFactory.heartRate(count: count, device: nil, metadata: nil)),
            Scenario(
                name: "heartRate-deployment-watch",
                style: .deployment,
                samples: SampleFactory.heartRate(
                    count: count,
                    device: SampleFactory.watchWithoutUnitToken,
                    metadata: [HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1)]
                )
            ),
            Scenario(
                name: "heartRate-deployment-recordingDevice",
                style: .deployment,
                samples: SampleFactory.heartRate(
                    count: count,
                    device: SampleFactory.deviceWithUnitToken,
                    metadata: [HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1), HKMetadataKeyTimeZone: "America/Los_Angeles"]
                )
            ),
            Scenario(name: "stepCount-minimal", style: .minimal, samples: SampleFactory.stepCount(count: count)),
            Scenario(name: "stepCount-deployment", style: .deployment, samples: SampleFactory.stepCount(count: count)),
            Scenario(
                name: "workout-noEvents-deployment",
                style: .deployment,
                samples: SampleFactory.workouts(count: max(100, count / 10), withEvents: false)
            ),
            Scenario(
                name: "workout12segments-deployment",
                style: .deployment,
                samples: SampleFactory.workouts(count: max(100, count / 10), withEvents: true)
            )
        ]
    }

    @Test(.enabled(if: BenchEnvironment.only != "workout-diagnose"))
    func baselineThroughput() throws {
        let report = BenchReport()
        defer { report.flush() }
        let count = BenchEnvironment.sampleCount
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let start = Memory.footprint()
        report.line("config build=\(configuration) N=\(count) runs=\(BenchEnvironment.runs) cores=\(ProcessInfo.processInfo.activeProcessorCount) "
            + "os=\(ProcessInfo.processInfo.operatingSystemVersionString) footprintMB=\(Memory.megabytes(start.current))")

        let scope = BenchScope()
        if let phase = BenchEnvironment.profile {
            try runProfileLoop(phase: phase, scope: scope, report: report)
            return
        }
        for scenario in Self.scenarios(count: count) where BenchEnvironment.only == nil || BenchEnvironment.only == scenario.name {
            var run = ScenarioRun(scenario: scenario, scope: scope, report: report)
            guard try warmUp(&run) else {
                continue
            }
            try measureConvert(&run)
            try measureEncode(&run)
            #if !GROVE_BENCH_NO_PASS_TIMING
            try measureValidationPasses(run)
            #endif
            try measureFoundationWork(run)
            try measureConstruction(run)
        }
        if BenchEnvironment.only == nil || BenchEnvironment.only == "concurrent" {
            try runConcurrent(scope: scope, count: count, report: report)
        }
        let end = Memory.footprint()
        report.line("done footprintMB=\(Memory.megabytes(end.current)) lifetimePeakMB=\(Memory.megabytes(end.peak))")
    }

    /// Why the converter refuses a synthetic workout: prints the claims the validator compares.
    @Test(.enabled(if: BenchEnvironment.only == "workout-diagnose"))
    func workoutDiagnose() throws {
        let scope = BenchScope()
        for withEvents in [false, true] {
            let sample = SampleFactory.workouts(count: 1, withEvents: withEvents)[0]
            let context = scope.context(for: sample, sequence: 1, style: .deployment)
            let type = try #require(HealthKitSourceType(sample))
            let output = try #require(HealthKitCatalog.primaryOutput(for: type))
            let binding = try #require(HealthKitCatalog.binding(for: sample))
            let envelope = try HealthKitConverter.graphEnvelope(
                for: sample, context: context, outputRole: output.role, outputDiscriminator: output.discriminator
            )
            let observation = try HealthKitConverter.observation(for: sample, binding: binding, graphContext: envelope.graphContext)
            let profiles = ExchangeGraph.canonicalStrings(observation.meta?.profile ?? [])
            let admitted = Set(ExchangeGraph.canonicalStrings(
                ProfileClaims.adapterProvenanceTargetProfiles[HealthKitContract.conversionProvenanceProfile.value!.url.absoluteString] ?? []
            ))
            print("BENCH diagnose withEvents=\(withEvents) type=\(type.rawValue) role=\(output.role)/\(output.discriminator) "
                + "primaryProfiles=\(profiles) admittedCount=\(admitted.count) primaryAdmitted=\(!admitted.isDisjoint(with: profiles))")
            let workout = try #require(sample as? HKWorkout)
            let segments = try HealthKitConverter.workoutSegments(workout, envelope: envelope)
            for segment in segments.prefix(1) {
                let segmentProfiles = ExchangeGraph.canonicalStrings(segment.observation.meta?.profile ?? [])
                print("BENCH diagnose segments=\(segments.count) segmentProfiles=\(segmentProfiles) "
                    + "segmentAdmitted=\(!admitted.isDisjoint(with: segmentProfiles))")
            }
            do {
                _ = try HealthKitConverter().convert(sample, context: context)
                print("BENCH diagnose withEvents=\(withEvents) convert=OK")
            } catch {
                print("BENCH diagnose withEvents=\(withEvents) convert=REFUSED \(error)")
            }
        }
    }

    /// First-use costs (catalog statics, Foundation coder caches) are reported, not averaged in. Returns false
    /// when the converter refuses the scenario's input, after reporting what a refusal costs.
    private func warmUp(_ run: inout ScenarioRun) throws -> Bool {
        let firstContext = run.scope.context(for: run.samples[0], sequence: 1, style: run.scenario.style)
        do {
            _ = try autoreleasepool { try run.converter.convert(run.samples[0], context: firstContext) }
        } catch {
            let refusalSeconds = Stopwatch.seconds {
                for (index, sample) in run.samples.enumerated() {
                    let context = run.scope.context(for: sample, sequence: UInt64(index + 1), style: run.scenario.style)
                    _ = autoreleasepool { try? run.converter.convert(sample, context: context) }
                }
            }
            let diagnostic = (error as? HealthKitConversionError)?.diagnostic
            run.report.line("scenario=\(run.name) N=\(run.count) REFUSED error=\(diagnostic?.code ?? String(describing: error)) "
                + "at \(diagnostic?.location ?? "?") phase=refusal \(run.rate(refusalSeconds))")
            return false
        }
        let secondContext = run.scope.context(for: run.samples[1], sequence: 2, style: run.scenario.style)
        let coldSeconds = try Stopwatch.seconds {
            _ = try autoreleasepool { try run.converter.convert(run.samples[1], context: secondContext) }
        }
        for index in 0..<min(Self.warmUpCount, run.count) {
            let context = run.scope.context(for: run.samples[index], sequence: UInt64(index + 1), style: run.scenario.style)
            _ = try autoreleasepool { try run.converter.convert(run.samples[index], context: context) }
        }
        run.report.line("scenario=\(run.name) N=\(run.count) secondCallMs=\(String(format: "%.2f", coldSeconds * 1_000))")

        // (0) Per-sample context construction, the way a consumer has to do it today.
        var contexts: [HealthKitConversionContext] = []
        contexts.reserveCapacity(run.count)
        let contextSeconds = Stopwatch.seconds {
            for (index, sample) in run.samples.enumerated() {
                contexts.append(run.scope.context(for: sample, sequence: UInt64(index + 1), style: run.scenario.style))
            }
        }
        run.contexts = contexts
        run.report.line("scenario=\(run.name) phase=context-construction \(run.rate(contextSeconds))")
        return true
    }

    /// (a) convert() total, results discarded, one autorelease pool per sample as MyHeartCounts does; then a retained pass.
    private func measureConvert(_ run: inout ScenarioRun) throws {
        var convertRuns: [Double] = []
        let before = Memory.footprint()
        for _ in 0..<BenchEnvironment.runs {
            convertRuns.append(try Stopwatch.seconds {
                for index in 0..<run.count {
                    _ = try run.convert(index)
                }
            })
        }
        let after = Memory.footprint()
        run.bestConvertSeconds = convertRuns.min()!
        let medianConvert = convertRuns.sorted()[convertRuns.count / 2]
        run.report.line("scenario=\(run.name) phase=convert-total(best) \(run.rate(run.bestConvertSeconds))")
        run.report.line("scenario=\(run.name) phase=convert-total(median) \(run.rate(medianConvert)) runs="
            + convertRuns.map { String(format: "%.3f", $0) }.joined(separator: ","))
        run.report.line("scenario=\(run.name) memory footprintBeforeMB=\(Memory.megabytes(before.current)) "
            + "footprintAfterMB=\(Memory.megabytes(after.current)) lifetimePeakMB=\(Memory.megabytes(after.peak))")

        var conversions: [HealthKitConversionSet] = []
        conversions.reserveCapacity(run.count)
        let retainedSeconds = try Stopwatch.seconds {
            for index in 0..<run.count {
                conversions.append(try run.convert(index))
            }
        }
        run.conversions = conversions
        let retained = Memory.footprint()
        let retainedBytes = retained.current > after.current ? retained.current - after.current : 0
        run.report.line("scenario=\(run.name) phase=convert-total(retained) \(run.rate(retainedSeconds)) "
            + "footprintMB=\(Memory.megabytes(retained.current)) retainedKBPerConversion=\(retainedBytes / UInt64(run.count) / 1_024)")
    }

    /// (b) JSONEncoder().encode(bundle) alone, the staging re-encode, and the exact production tail of convert().
    private func measureEncode(_ run: inout ScenarioRun) throws {
        var encoded: [Data] = []
        encoded.reserveCapacity(run.count)
        run.encodeSeconds = try Stopwatch.seconds {
            for conversion in run.conversions {
                encoded.append(try autoreleasepool { try JSONEncoder().encode(conversion.bundle) })
            }
        }
        run.encoded = encoded
        let bytes = encoded.reduce(0) { $0 + $1.count }
        let entries = run.conversions.reduce(0) { $0 + ($1.bundle.entry?.count ?? 0) }
        let warnings = run.conversions.reduce(0) { $0 + $1.warnings.count }
        run.report.line("scenario=\(run.name) phase=encode-bundle \(run.rate(run.encodeSeconds)) bytesPerBundle=\(bytes / run.count) "
            + "entriesPerBundle=\(String(format: "%.1f", Double(entries) / Double(run.count))) "
            + "warningsPerSample=\(String(format: "%.2f", Double(warnings) / Double(run.count)))")
        if let directory = BenchEnvironment.dumpDirectory {
            // The first graph's validated bytes, plus the size of each entry's resource, for inspecting what an event carries.
            try encoded[0].write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(run.name).json"))
            let sizes = try (run.conversions[0].bundle.entry ?? []).map { entry in
                "\(entry.resource?.resourceType ?? "?")=\(try JSONEncoder().encode(entry).count)"
            }
            run.report.line("scenario=\(run.name) entry-bytes \(sizes.joined(separator: " "))")
        }
        // What MyHeartCounts stages today: a second encode with sorted keys and unescaped slashes.
        let stagingEncoder = JSONEncoder()
        stagingEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var stagedBytes = 0
        let stagedSeconds = try Stopwatch.seconds {
            for conversion in run.conversions {
                stagedBytes += try autoreleasepool { try stagingEncoder.encode(conversion.bundle).count }
            }
        }
        run.report.line("scenario=\(run.name) phase=encode-bundle(sortedKeys+withoutEscapingSlashes) \(run.rate(stagedSeconds)) "
            + "bytesPerBundle=\(stagedBytes / run.count)")
        // The graph's stored bytes are the encoder's bytes, so (b) is exactly what the graph already holds.
        #expect(run.conversions[0].graph.json.count == encoded[0].count)

        run.graphInitSeconds = try Stopwatch.seconds {
            for conversion in run.conversions {
                _ = try ExchangeGraph(kind: .active, eventIdentifier: conversion.graph.eventIdentifier, bundle: conversion.bundle)
            }
        }
        run.report.line("scenario=\(run.name) phase=graph-init(encode+parse+validate) \(run.rate(run.graphInitSeconds))")
    }

    #if !GROVE_BENCH_NO_PASS_TIMING
    /// The validation passes in production order. Each graph gets a fresh document, and later passes reuse the
    /// identifier caches the earlier ones filled, exactly as ExchangeGraph.validate does.
    private func measureValidationPasses(_ run: ScenarioRun) throws {
        let passNames = [
            "document(JSONSerialization+entry-map)", "entry-resource-policy", "entry-node-digests", "resource-identifiers",
            "identifier-system-roles", "entry-keys", "governed-reference-targets", "active-lifecycle"
        ]
        var passNanoseconds = [UInt64](repeating: 0, count: passNames.count)
        for (conversion, data) in zip(run.conversions, run.encoded) {
            try autoreleasepool {
                let bundle = conversion.bundle
                let entries = bundle.entry ?? []
                var mark = DispatchTime.now().uptimeNanoseconds
                func lap(_ pass: Int) {
                    let now = DispatchTime.now().uptimeNanoseconds
                    passNanoseconds[pass] += now - mark
                    mark = now
                }
                let document = ExchangeGraph.ValidationDocument(bundle: bundle, jsonData: data)
                lap(0)
                try ExchangeGraph.validateEntryResourcePolicy(kind: .active, entries: entries, document: document)
                lap(1)
                try ExchangeGraph.validateEntryNodeDigests(entries: entries, eventIdentifier: conversion.graph.eventIdentifier)
                lap(2)
                try ExchangeGraph.validateResourceIdentifiers(entries: entries, document: document)
                lap(3)
                try ExchangeIdentity.validateIdentifierSystemRoles(inBundleJSON: document.bundleObject())
                lap(4)
                try ExchangeGraph.validateEntryKeys(entries: entries, document: document)
                lap(5)
                try ExchangeGraph.validateGovernedReferenceTargets(entries: entries, document: document)
                lap(6)
                try ExchangeGraph.validateActive(entries: entries, document: document)
                lap(7)
            }
        }
        let passTotal = passNanoseconds.reduce(0, +)
        let perPass = zip(passNames, passNanoseconds).map { name, nanoseconds in
            "\(name)=\(String(format: "%.1f", Double(nanoseconds) / Double(run.count) / 1_000))us"
        }
        run.report.line("scenario=\(run.name) validation-passes total=\(String(format: "%.1f", Double(passTotal) / Double(run.count) / 1_000))us/sample: "
            + perPass.joined(separator: " "))
    }
    #endif

    /// (c) Re-validation of serialized bytes alone, and the pieces of validation that are pure Foundation work.
    private func measureFoundationWork(_ run: ScenarioRun) throws {
        let revalidateSeconds = try Stopwatch.seconds {
            for data in run.encoded {
                _ = try ExchangeGraph(kind: .active, jsonData: data)
            }
        }
        run.report.line("scenario=\(run.name) phase=revalidate-jsonData \(run.rate(revalidateSeconds))")
        let parseSeconds = try Stopwatch.seconds {
            for data in run.encoded {
                _ = try autoreleasepool { try JSONSerialization.jsonObject(with: data) }
            }
        }
        run.report.line("scenario=\(run.name) phase=JSONSerialization-parse \(run.rate(parseSeconds))")
        let decodeSeconds = try Stopwatch.seconds {
            for data in run.encoded {
                _ = try autoreleasepool { try JSONDecoder().decode(ModelsR4.Bundle.self, from: data) }
            }
        }
        run.report.line("scenario=\(run.name) phase=JSONDecoder-decode-bundle \(run.rate(decodeSeconds))")
    }

    /// Construction pieces: identities + device snapshots + study context, then the clinical content alone.
    private func measureConstruction(_ run: ScenarioRun) throws {
        var envelopes: [HealthKitConverter.GraphEnvelope] = []
        envelopes.reserveCapacity(run.count)
        let type = HealthKitSourceType(run.samples[0])!
        let output = HealthKitCatalog.primaryOutput(for: type)!
        let envelopeSeconds = try Stopwatch.seconds {
            for index in 0..<run.count {
                envelopes.append(try HealthKitConverter.graphEnvelope(
                    for: run.samples[index],
                    context: run.contexts[index],
                    outputRole: output.role,
                    outputDiscriminator: output.discriminator
                ))
            }
        }
        run.report.line("scenario=\(run.name) phase=graph-envelope(identities+devices+study) \(run.rate(envelopeSeconds))")
        let binding = HealthKitCatalog.binding(for: run.samples[0])!
        let observationSeconds = try Stopwatch.seconds {
            for index in 0..<run.count {
                _ = try HealthKitConverter.observation(for: run.samples[index], binding: binding, graphContext: envelopes[index].graphContext)
            }
        }
        run.report.line("scenario=\(run.name) phase=observation-content \(run.rate(observationSeconds))")
        let studySeconds = try Stopwatch.seconds {
            for context in run.contexts {
                _ = try context.event.studyContext()
            }
        }
        run.report.line("scenario=\(run.name) phase=study-context \(run.rate(studySeconds))")

        let validateOnly = run.graphInitSeconds - run.encodeSeconds
        let construction = run.bestConvertSeconds - run.graphInitSeconds
        func share(_ seconds: Double) -> String {
            String(format: "%.1f%%", seconds / run.bestConvertSeconds * 100)
        }
        func perSample(_ seconds: Double) -> String {
            String(format: "%.1f", seconds / Double(run.count) * 1_000_000)
        }
        run.report.line("scenario=\(run.name) breakdown-of-convert(best): construction=\(share(construction)) "
            + "encode=\(share(run.encodeSeconds)) parse+validate=\(share(validateOnly)) "
            + "[usPerSample construction=\(perSample(construction)) encode=\(perSample(run.encodeSeconds)) parse+validate=\(perSample(validateOnly))]")
    }

    /// Loops one phase over the deployment heart-rate workload so `sample`/Instruments can attach by pid.
    private func runProfileLoop(phase: String, scope: BenchScope, report: BenchReport) throws {
        let samples = SampleFactory.heartRate(
            count: 1_000,
            device: SampleFactory.watchWithoutUnitToken,
            metadata: [HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1)]
        )
        let contexts = samples.enumerated().map { index, sample in
            scope.context(for: sample, sequence: UInt64(index + 1), style: .deployment)
        }
        let converter = HealthKitConverter()
        let conversions = try zip(samples, contexts).map { try converter.convert($0, context: $1) }
        report.line("profile phase=\(phase) pid=\(ProcessInfo.processInfo.processIdentifier) seconds=\(BenchEnvironment.profileSeconds)")
        let deadline = Date().addingTimeInterval(BenchEnvironment.profileSeconds)
        var iterations = 0
        while Date() < deadline {
            for index in samples.indices {
                try autoreleasepool {
                    if phase == "graph-init" {
                        _ = try ExchangeGraph(
                            kind: .active,
                            eventIdentifier: conversions[index].graph.eventIdentifier,
                            bundle: conversions[index].bundle
                        )
                    } else {
                        _ = try converter.convert(samples[index], context: contexts[index])
                    }
                }
            }
            iterations += samples.count
        }
        report.line("profile phase=\(phase) iterations=\(iterations)")
    }

    /// Whether the converter scales across threads: the same deployment heart-rate workload split over T threads.
    private func runConcurrent(scope: BenchScope, count: Int, report: BenchReport) throws {
        let samples = SampleFactory.heartRate(
            count: count,
            device: SampleFactory.watchWithoutUnitToken,
            metadata: [HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1)]
        )
        let contexts = samples.enumerated().map { index, sample in
            scope.context(for: sample, sequence: UInt64(index + 1), style: .deployment)
        }
        let converter = HealthKitConverter()
        for threads in [1, 2, 4, 6, 8] {
            let failures = ManagedFailureCount()
            let seconds = Stopwatch.seconds {
                DispatchQueue.concurrentPerform(iterations: threads) { thread in
                    var index = thread
                    while index < count {
                        do {
                            _ = try autoreleasepool { try converter.convert(samples[index], context: contexts[index]) }
                        } catch {
                            failures.increment()
                        }
                        index += threads
                    }
                }
            }
            #expect(failures.value == 0)
            report.line("scenario=concurrent-heartRate-deployment-watch threads=\(threads) N=\(count) "
                + String(format: "%.3fs %.1f/s", seconds, Double(count) / seconds))
        }
    }
}

#endif
