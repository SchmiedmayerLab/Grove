//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
@testable import GroveQuestionnaireExtraction
import ModelsR4
import Testing


/// What a Questionnaire record states beyond the shared record contract: the carried response's content key, which it
/// repeats in `grove-context-snapshot` (its one `identifier` holds the submission's), and the writer's host facts.
@Suite("Questionnaire Records")
struct QuestionnaireRecordTests {
    private typealias Fixtures = QuestionnaireExportFixtures

    /// The entry key a response entry states.
    private static func entryKey(of entry: BundleEntry) throws -> Identifier {
        let keys = entry.extension?.filter { $0.url == Canonicals.entryKey } ?? []
        guard keys.count == 1, case .identifier(let key)? = keys.first?.value else {
            throw CocoaError(.coderValueNotFound)
        }
        return key
    }

    /// The values of the response's `grove-context-snapshot` extensions.
    private static func statedKeys(of response: ModelsR4.QuestionnaireResponse) -> [Identifier] {
        (response.extension ?? []).filter { $0.url == Canonicals.contextSnapshot }.compactMap { snapshot in
            if case .identifier(let identifier)? = snapshot.value { identifier } else { nil }
        }
    }

    private static func snapshot(of response: ModelsR4.QuestionnaireResponse) throws -> RoledIdentifier {
        try Fixtures.identityScope.contentSnapshot(of: response, subject: Fixtures.pseudonym, role: .context(.questionnaireResponse))
    }

    /// The bytes of `record` with its QuestionnaireResponse changed by `change`.
    private static func json(of record: ExchangeRecord, changingResponse change: (inout [String: Any]) -> Void) throws -> Data {
        var bundle = try #require(try JSONSerialization.jsonObject(with: record.json) as? [String: Any])
        var entries = try #require(bundle["entry"] as? [[String: Any]])
        let index = try #require(entries.firstIndex { ($0["resource"] as? [String: Any])?["resourceType"] as? String == "QuestionnaireResponse" })
        var resource = try #require(entries[index]["resource"] as? [String: Any])
        change(&resource)
        entries[index]["resource"] = resource
        bundle["entry"] = entries
        return try JSONSerialization.data(withJSONObject: bundle)
    }

    private static func removingSnapshot(_ resource: inout [String: Any]) {
        resource["extension"] = (resource["extension"] as? [[String: Any]])?.filter { $0["url"] as? String != Canonicals.contextSnapshotValue }
    }

    /// The guide's pair with `writer` as its writer context.
    private static func record(writer: QuestionnaireWriterContext) async throws -> ExchangeRecord {
        try await Fixtures.exported(Fixtures.guideRecord { $0.apply(writerContext: writer) })
    }

    // MARK: The Response's Content Key

    @Test("The carried response keeps the submission's identifier and repeats its entry key in one extension")
    func responseRepeatsItsEntryKey() async throws {
        let record = try await Fixtures.exported(Fixtures.guideRecord())
        let entry = try record.responseEntry
        let response = try record.response
        let key = try Self.entryKey(of: entry)
        #expect(try RoledIdentifier(key).role == .contextSnapshot)
        #expect(Self.statedKeys(of: response) == [key])
        #expect(response.identifier == (try Fixtures.guideRecord()).response.identifier)
        #expect(try RoledIdentifier(key).fullURLString == entry.fullUrl?.value?.url.absoluteString)
    }

    @Test("The response's key digests neither its id nor its grove-context-snapshot extension")
    func keyExcludesIdAndItsOwnExtension() async throws {
        let response = try await Fixtures.exported(Fixtures.guideRecord()).response
        let key = try Self.snapshot(of: response)
        #expect(key.fhirIdentifier == Self.statedKeys(of: response).first)
        var bare = response
        bare.id = nil
        bare.extension = response.extension?.filter { $0.url != Canonicals.contextSnapshot }
        #expect(try Self.snapshot(of: bare) == key)
        var changed = response
        changed.language = "es-US".asFHIRStringPrimitive()
        #expect(try Self.snapshot(of: changed) != key)
    }

    @Test("A response that already carries a key is keyed by its content alone")
    func anInputKeyIsReplaced() async throws {
        let record = try await Fixtures.exported(Fixtures.guideRecord())
        let stale = Extension(
            url: Canonicals.contextSnapshot,
            value: .identifier(try Self.snapshot(of: Fixtures.guideRecord { $0.language = "es-US".asFHIRStringPrimitive() }.response).fhirIdentifier)
        )
        let restated = try await Fixtures.exported(Fixtures.guideRecord { $0.extension = ($0.extension ?? []) + [stale] })
        #expect(restated == record)
    }

    @Test("An amended response is a new snapshot under the same submission identifier")
    func amendmentIsANewSnapshot() async throws {
        let guide = try await Fixtures.exported(Fixtures.guideRecord())
        let amended = try await Fixtures.exported(Fixtures.guideRecord { $0.status = FHIRPrimitive(.amended) })
        #expect(try amended.response.identifier == guide.response.identifier)
        #expect(try amended.responseEntry.fullUrl != guide.responseEntry.fullUrl)
        let responseURL = try amended.responseEntry.fullUrl?.value?.url.absoluteString
        for observation in try amended.observations {
            #expect(observation.derivedFrom?.first?.reference?.value?.string == responseURL)
        }
    }

    @Test("A grove-context-snapshot that is missing, repeated or not the entry key is refused")
    func theExtensionMustMatchTheEntryKey() async throws {
        let record = try await Fixtures.exported(Fixtures.guideRecord())
        let other = try await Fixtures.exported(Fixtures.guideRecord { $0.language = "es-US".asFHIRStringPrimitive() })
        let otherResponse = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(other.response)) as? [String: Any])
        let otherExtension = try #require((otherResponse["extension"] as? [[String: Any]])?.last)

        let missing = try Self.json(of: record) { Self.removingSnapshot(&$0) }
        let repeated = try Self.json(of: record) { resource in
            resource["extension"] = (resource["extension"] as? [[String: Any]] ?? []) + [otherExtension]
        }
        let differing = try Self.json(of: record) { resource in
            Self.removingSnapshot(&resource)
            resource["extension"] = (resource["extension"] as? [[String: Any]] ?? []) + [otherExtension]
        }
        for tampered in [missing, repeated, differing] {
            #expect {
                try ExchangeRecord(validating: tampered)
            } throws: { error in
                (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.context-snapshot-extension"
            }
        }
    }

    // MARK: Records

    @Test("A record reads back from its own bytes, and its version recomputes")
    func recordRoundTrips() async throws {
        let record = try await Fixtures.exported(Fixtures.guideRecord())
        #expect(record.kind == .active)
        #expect(record.subject == (try Fixtures.pseudonym))
        #expect(try record.provenance.recorded.value?.description == "2026-08-28T15:32:05Z")
        #expect(try ExchangeRecord(validating: record.json) == record)
        try record.verifyVersion(in: Fixtures.identityScope)
    }

    @Test("Each conversion Provenance repeats the record version it is keyed by")
    func provenanceRepeatsItsVersion() async throws {
        let record = try await Fixtures.exported(Fixtures.guideRecord())
        let extensions = try record.provenance.extension ?? []
        #expect(extensions.count == 1)
        #expect(extensions.first?.url == Canonicals.recordVersion)
        #expect(extensions.first?.value == .identifier(record.version.identifier.fhirIdentifier))
    }

    @Test("Records of two responses pack into one Bundle and share their nodes")
    func recordsPackIntoOneBundle() async throws {
        let first = try await Fixtures.exported(Fixtures.guideRecord())
        let second = try await Fixtures.exported(Fixtures.guideRecord { response in
            response.identifier = Identifier(system: response.identifier?.system, value: "home-vitals-2026-08-29")
        })
        #expect(first.sourceRecord != second.sourceRecord)
        var packer = ExchangeBundlePacker(kind: .active)
        #expect(try packer.add(first) == .added)
        #expect(try packer.add(second) == .added)
        #expect(try packer.add(first) == .duplicate)
        let graph = try packer.bundle(packedAt: Fixtures.instant.addingTimeInterval(60))
        let resources = graph.bundle.entry?.compactMap { $0.resource?.resourceType } ?? []
        // Both records share the Patient and the writer's Devices; each states its own response.
        #expect(resources.filter { $0 == "Patient" }.count == 1)
        #expect(resources.filter { $0 == "Device" }.count == 2)
        #expect(resources.filter { $0 == "QuestionnaireResponse" }.count == 2)
        #expect(resources.filter { $0 == "Observation" }.count == 4)
        #expect(resources.filter { $0 == "Provenance" }.count == 2)
        let records = try graph.records()
        #expect(records.map(\.version) == [first.version, second.version])
        for record in records {
            try record.verifyVersion(in: Fixtures.identityScope)
        }
    }

    @Test("A second version of a response waits for the next Bundle")
    func secondVersionIsDeferred() async throws {
        let first = try await Fixtures.exported(Fixtures.guideRecord())
        let amended = try await Fixtures.exported(Fixtures.guideRecord { $0.status = FHIRPrimitive(.amended) })
        var packer = ExchangeBundlePacker(kind: .active)
        #expect(try packer.add(first) == .added)
        #expect(try packer.add(amended) == .deferred)
    }

    // MARK: The Writer's Host

    @Test("Every host fact the writer states reaches the host snapshot")
    func hostFactsReachTheSnapshot() async throws {
        let writer = try Fixtures.writer(
            hostModel: "iPhone18,2",
            hostOperatingSystemName: "iOS",
            hostOperatingSystemVersion: "27.0",
            hostOperatingSystemBuild: "24A100"
        )
        let host = try #require(try await Self.record(writer: writer).devices.first { $0.parent == nil })
        #expect(host.modelNumber?.value?.string == "iPhone18,2")
        #expect(host.statedVersions == ["os-name": "iOS", "os-version": "27.0", "os-build": "24A100"])
    }

    @Test("A changed operating-system name or build is another host snapshot")
    func hostFactsKeyTheSnapshot() async throws {
        func hostURL(name: String, build: String) async throws -> String? {
            let writer = try Fixtures.writer(hostOperatingSystemName: name, hostOperatingSystemVersion: "27.0", hostOperatingSystemBuild: build)
            return try await Self.record(writer: writer).devices.first { $0.parent != nil }?.parent?.reference?.value?.string
        }
        let base = try await hostURL(name: "iOS", build: "24A100")
        let renamed = try await hostURL(name: "iPadOS", build: "24A100")
        let rebuilt = try await hostURL(name: "iOS", build: "24A101")
        #expect(Set([base, renamed, rebuilt]).count == 3)
    }

    @Test("A writer stating no model still states its host, and one stating no operating-system version states none")
    func hostNeedsOnlyItsOperatingSystemVersion() async throws {
        let modelless = try await Self.record(writer: Fixtures.writer(hostOperatingSystemVersion: "27.0"))
        let host = try #require(try modelless.devices.first { $0.parent == nil })
        #expect(host.meta?.profile == [Profile.groveHostDevice])
        #expect(host.modelNumber == nil)
        #expect(host.statedVersions == ["os-version": "27.0"])
        #expect(try modelless.devices.count == 2)

        let versionless = try await Self.record(writer: Fixtures.writer(hostModel: "iPhone18,2", hostOperatingSystemName: "iOS"))
        #expect(try versionless.devices.count == 1)
        #expect(try versionless.devices.first?.parent == nil)
    }

    // MARK: The Writer Context

    @Test("The writer context round-trips through its extension, host facts included")
    func writerContextRoundTrips() throws {
        let writer = try Fixtures.writer(
            build: "1502",
            hostModel: "iPhone18,2",
            hostOperatingSystemName: "iOS",
            hostOperatingSystemVersion: "27.0",
            hostOperatingSystemBuild: "24A100"
        )
        let response = try Fixtures.guideRecord { $0.apply(writerContext: writer) }.response
        #expect(try response.writerContext() == writer)
    }

    @Test("A blank host fact is refused at the writer context, in the extension too")
    func emptyHostFactsAreRefused() throws {
        #expect(throws: QuestionnaireWriterContextError.emptyHostOperatingSystemName) {
            try Fixtures.writer(hostOperatingSystemName: "")
        }
        #expect(throws: QuestionnaireWriterContextError.emptyHostOperatingSystemBuild) {
            try Fixtures.writer(hostOperatingSystemBuild: "")
        }
        var response = try Fixtures.guideRecord().response
        let index = try #require(response.extension?.firstIndex { $0.url == QuestionnaireWriterContext.canonicalURL })
        let build = try #require(response.extension?[index].extension?.firstIndex { $0.url.value?.url.absoluteString == "hostOperatingSystemBuild" })
        response.extension?[index].extension?[build].value = .string("".asFHIRStringPrimitive())
        #expect(throws: ObservationExtractionError.incompleteWriterContext) {
            try response.writerContext()
        }
    }

    @Test("The current writer states the host's operating-system name the app captured, and its build")
    func currentWriterStatesTheHost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let info: [String: Any] = [
            "CFBundleIdentifier": "org.grovealliance.example.client",
            "CFBundleName": "Grove Questionnaire Client",
            "CFBundleShortVersionString": "1.5.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        let system: IdentifierSystem = "https://study.example.org/fhir/NamingSystem/application"
        let writer = try QuestionnaireWriterContext.current(applicationIdentifierSystem: system, hostOperatingSystemName: "iOS", bundle: bundle)
        #expect(writer.hostOperatingSystemName == "iOS")
        #expect(writer.hostOperatingSystemBuild == HostDevice.current().operatingSystemBuild)
        let unnamed = try QuestionnaireWriterContext.current(applicationIdentifierSystem: system, bundle: bundle)
        #expect(unnamed.hostOperatingSystemName == nil)
    }
}
