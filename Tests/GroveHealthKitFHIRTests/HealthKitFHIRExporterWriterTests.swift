//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The bundle identifiers of the sources a classifying closure was asked about.
private final class AskedSources: @unchecked Sendable { // `asked` is guarded by `lock`.
    private let lock = NSLock()
    private var asked: [String] = []

    var bundleIdentifiers: [String] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return asked
    }

    func record(_ source: HKSource) {
        lock.lock()
        defer {
            lock.unlock()
        }
        asked.append(source.bundleIdentifier)
    }
}


/// W1 to W4: only the caller's classification states a writer. `HKSourceRevision` does not say whether a source
/// is an application or a device, and the HealthKit guide forbids classifying it from the bundle identifier's
/// shape, the source name or the product type (`mapping.md`, writer rules); the recording Device stays whatever
/// the recording-device policy resolves from `HKDevice`.
@Suite
struct HealthKitFHIRExporterWriterTests {
    private typealias Fixtures = ExporterFixtures

    /// An Apple per-device source: the watch that recorded the sample itself, as HealthKit names it.
    private static let watchSource = StoredSampleFixtures.Writer(
        name: "Lukas's Apple Watch",
        bundleIdentifier: "com.apple.health.6C4B1D1E-0000-4000-8000-000000000009",
        version: "26.1",
        productType: "Watch7,12"
    )

    /// An application the callers below never classify.
    private static let otherApplication = StoredSampleFixtures.Writer(
        name: "Other Writer",
        bundleIdentifier: "org.example.other",
        version: "7",
        productType: "iPhone17,1"
    )

    /// The converting application's bundle identifier: the only one a graph without a writer states.
    private static let converterBundleIdentifier = ExporterFixtures.base.application.bundleIdentifier

    private static func devices(_ bundle: ModelsR4.Bundle) -> [(url: String?, device: Device)] {
        (bundle.entry ?? []).compactMap { entry in
            entry.resource?.get(if: Device.self).map { (entry.fullUrl?.value?.url.absoluteString, $0) }
        }
    }

    /// Every clear Apple bundle identifier the graph's Devices state.
    private static func statedBundleIdentifiers(_ bundle: ModelsR4.Bundle) -> Set<String> {
        Set(devices(bundle).flatMap { _, device in
            (device.identifier ?? [])
                .filter { $0.system == HealthKitContract.appleBundleIdentifierSystem }
                .compactMap { $0.value?.value?.string }
        })
    }

    /// The Device stating `bundleIdentifier`, with its fullUrl.
    private static func device(stating bundleIdentifier: String, in bundle: ModelsR4.Bundle) -> (url: String?, device: Device)? {
        devices(bundle).first { _, device in
            device.identifier?.contains { $0.value?.value?.string == bundleIdentifier } == true
        }
    }

    private static func recordingDevices(_ bundle: ModelsR4.Bundle) -> [Device] {
        devices(bundle).map(\.device).filter { $0.meta?.profile?.contains(Profile.groveRecordingDevice) == true }
    }

    /// The reference of the Provenance agent typed `author`, if any.
    private static func author(_ bundle: ModelsR4.Bundle) -> String? {
        let provenance = bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first
        let author = provenance?.entity?.first?.agent?.first { agent in
            agent.type?.coding?.contains { $0.code?.value?.string == "author" } == true
        }
        return author?.who.reference?.value?.string
    }

    /// Whether the graph states the application writer `writer`, exactly as the sample's `HKSourceRevision` names it.
    private static func statesWriter(_ writer: StoredSampleFixtures.Writer, in bundle: ModelsR4.Bundle) throws -> Bool {
        let stated = try #require(device(stating: writer.bundleIdentifier, in: bundle))
        #expect(stated.device.deviceName?.first?.name.value?.string == writer.name)
        #expect(stated.device.version?.contains { $0.value.value?.string == writer.version } == true)
        #expect(author(bundle) == stated.url, "the writer is the Provenance author")
        return true
    }

    /// Asserts that the graph states no writer and no author, and no Device names the source.
    private static func statesNoWriter(_ bundle: ModelsR4.Bundle, source: StoredSampleFixtures.Writer) {
        #expect(statedBundleIdentifiers(bundle) == [converterBundleIdentifier], "\(source.bundleIdentifier) is stated")
        #expect(author(bundle) == nil, "the Provenance names an author for \(source.bundleIdentifier)")
        #expect(devices(bundle).allSatisfy { $0.device.deviceName?.first?.name.value?.string != source.name })
    }

    private static func exports(
        _ exporter: HealthKitFHIRExporter,
        _ samples: [HKSample]
    ) throws -> [UUID: HealthKitFHIRExporter.Export] {
        let (exports, _) = try Fixtures.collect(exporter, samples: samples)
        return Dictionary(uniqueKeysWithValues: exports.map { ($0.source.uuid, $0) })
    }

    @Test("W1: by default an Apple per-device source states no writer, no author and no recording Device of its own")
    func exporterDefaultStatesNoWriter() throws {
        let exporter = try Fixtures.exporter()
        guard case .omit = exporter.options.writer else {
            Issue.record("the default writer policy is \(exporter.options.writer), not omit")
            return
        }
        let bare = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x31), writer: Self.watchSource)
        let declined = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x32), device: GoldenFixtures.watchWithoutUnitToken, writer: Self.watchSource)
        let resolved = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x33), device: GoldenFixtures.watch, writer: Self.watchSource)
        let exports = try Self.exports(exporter, [bare, declined, resolved])
        let bundles = try [bare, declined, resolved].map { try #require(exports[$0.uuid]?.graph?.bundle) }
        for bundle in bundles {
            Self.statesNoWriter(bundle, source: Self.watchSource)
        }
        // No `HKDevice`: no recording Device and nothing to report.
        #expect(Self.recordingDevices(bundles[0]).isEmpty)
        #expect(exports[bare.uuid]?.warnings.isEmpty == true)
        // An `HKDevice` the policy declined: no recording Device, and the omission is reported.
        #expect(Self.recordingDevices(bundles[1]).isEmpty)
        #expect(exports[declined.uuid]?.warnings == [ExchangeGraphRule.mobileOmissionRecordingDevice.diagnostic])
        // An `HKDevice` the policy resolved: its recording Device, named by the `HKDevice`, and no warning.
        #expect(Self.recordingDevices(bundles[2]).map { $0.deviceName?.first?.name.value?.string } == ["Apple Watch"])
        #expect(exports[resolved.uuid]?.warnings.isEmpty == true)
    }

    @Test("W2: a listed bundle identifier states its application writer from the sample's own source revision; others state none")
    func listedApplicationsStateTheirWriter() throws {
        let exporter = try Fixtures.exporter { $0.writer = .applications([GoldenFixtures.foreignWriter.bundleIdentifier]) }
        let listed = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x41), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let unlisted = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x42), device: GoldenFixtures.watch, writer: Self.otherApplication)
        let watch = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x43), device: GoldenFixtures.watch, writer: Self.watchSource)
        let exports = try Self.exports(exporter, [listed, unlisted, watch])
        let listedExport = try #require(exports[listed.uuid])
        #expect(try Self.statesWriter(GoldenFixtures.foreignWriter, in: try #require(listedExport.graph?.bundle)))
        Self.statesNoWriter(try #require(exports[unlisted.uuid]?.graph?.bundle), source: Self.otherApplication)
        Self.statesNoWriter(try #require(exports[watch.uuid]?.graph?.bundle), source: Self.watchSource)
        // The listed source exports exactly as it does with every source classified as an application.
        let reference = try Fixtures.standalone(.sample(listed), as: listedExport.event, .applicationWriter)
        #expect(listedExport.graph?.json == reference.graph.json)
    }

    @Test("W3: a classifying closure is asked per source; an application states the revision's values, an omission nothing")
    func classifyingClosureDecidesPerSource() throws {
        let asked = AskedSources()
        let exporter = try Fixtures.exporter { options in
            options.writer = .classify { source in
                asked.record(source)
                return source.bundleIdentifier == GoldenFixtures.foreignWriter.bundleIdentifier ? .application : .omit
            }
        }
        let classified = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x51), writer: GoldenFixtures.foreignWriter)
        let omitted = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x52), writer: Self.otherApplication)
        let exports = try Self.exports(exporter, [classified, omitted])
        #expect(asked.bundleIdentifiers.sorted() == [Self.otherApplication.bundleIdentifier, GoldenFixtures.foreignWriter.bundleIdentifier].sorted())
        #expect(try Self.statesWriter(GoldenFixtures.foreignWriter, in: try #require(exports[classified.uuid]?.graph?.bundle)))
        Self.statesNoWriter(try #require(exports[omitted.uuid]?.graph?.bundle), source: Self.otherApplication)
    }

    @Test("A sample's writer-record identity and version travel whatever the writer policy says about its source")
    func writerRecordTravelsUnderEveryWriterPolicy() throws {
        let sample = try GoldenCase.attributedHeartRate(uuid: 0x61, writer: GoldenFixtures.foreignWriter, metadata: GoldenCase.syncMetadata)
        // The writing application's bundle identifier scopes the sync identifier, whether or not the caller classified it.
        let expected = try Fixtures.base.identityScope.writerRecord(
            writerApplication: BusinessIdentifier(
                system: IdentifierSystem(Canonicals.appleBundleIdentifierSystem),
                value: GoldenFixtures.foreignWriter.bundleIdentifier
            ),
            writerRecordID: "sync-abc"
        )
        let exporters: [(String, HealthKitFHIRExporter)] = try [
            ("the default", Fixtures.exporter()),
            ("omit", Fixtures.exporter { $0.writer = .omit }),
            ("applications listing it", Fixtures.exporter { $0.writer = .applications([GoldenFixtures.foreignWriter.bundleIdentifier]) }),
            ("applications listing another", Fixtures.exporter { $0.writer = .applications([Self.otherApplication.bundleIdentifier]) }),
            ("no applications", Fixtures.exporter { $0.writer = .applications([]) }),
            ("classified as omitted", Fixtures.exporter { $0.writer = .classify { _ in .omit } }),
            ("classified as an application", Fixtures.exporter { $0.writer = .classify { _ in .application } })
        ]
        for (policy, exporter) in exporters {
            let bundle = try #require(try Self.exports(exporter, [sample])[sample.uuid]?.graph?.bundle)
            let observation = try #require(bundle.entry?.compactMap { $0.resource?.get(if: ModelsR4.Observation.self) }.first)
            let writerRecords = (observation.identifier ?? []).filter { (try? RoledIdentifier($0).role) == .writerRecord }
            #expect(writerRecords.map { $0.value?.value?.string } == [expected.value], "under \(policy)")
            let versions = (observation.extension ?? []).filter { $0.url == Canonicals.writerRecordVersion }.map { version -> String? in
                guard case .string(let value)? = version.value else {
                    return nil
                }
                return value.value?.string
            }
            #expect(versions == ["3"], "under \(policy)")
        }
    }

    @Test("W4: no source file of the adapter names Apple's per-device bundle-identifier prefix")
    func noSourceNamesThePerDevicePrefix() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/GroveHealthKitFHIR", isDirectory: true)
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        try #require(!files.isEmpty, "no adapter sources at \(sources.path)")
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("\"com.apple.health."), "\(file) names the Apple per-device source prefix")
        }
    }
}

#endif
