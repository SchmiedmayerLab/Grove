//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import ModelsR4
import Testing


@Suite("Exchange records")
struct ExchangeRecordTests {
    private typealias Fixtures = ExchangeRecordFixtures

    @Test("A conversion Provenance repeats its record version, keyed as its entry")
    func recordVersionIsRepeated() throws {
        let record = try Fixtures.record()
        #expect(record.kind == .active)
        #expect(record.version.identifier.role == .recordVersion)
        let provenance = try #require(try Fixtures.resources(of: record).first { $0["resourceType"] as? String == "Provenance" })
        let extensions = try #require(provenance["extension"] as? [[String: Any]])
        #expect(extensions.count == 1)
        #expect(extensions[0]["url"] as? String == Canonicals.recordVersionValue)
        let identifier = try #require(extensions[0]["valueIdentifier"] as? [String: Any])
        #expect(identifier["value"] as? String == record.version.identifier.identifier.value)
        try record.verifyVersion(in: Fixtures.identityScope)
    }

    @Test("A record's json is canonical, with no Bundle.identifier, and states Provenance.recorded")
    func recordJSONIsCanonical() throws {
        let record = try Fixtures.record()
        #expect(try LosslessJSONValue(parsing: record.json).canonicalBytes() == record.json)
        let root = try #require(try JSONSerialization.jsonObject(with: record.json) as? [String: Any])
        #expect(root["identifier"] == nil)
        let provenance = try #require(try Fixtures.resources(of: record).first { $0["resourceType"] as? String == "Provenance" })
        #expect(root["timestamp"] as? String == provenance["recorded"] as? String)
    }

    @Test("A record reads back from its own bytes unchanged")
    func recordRoundTrips() throws {
        let record = try Fixtures.record()
        #expect(try ExchangeRecord(validating: record.json) == record)
    }

    @Test("A retried conversion repeats its version, and another instant or value is a new one")
    func versionsFollowContent() throws {
        let record = try Fixtures.record()
        #expect(try Fixtures.record() == record)
        let later = try Fixtures.record(at: Fixtures.instant.addingTimeInterval(1))
        #expect(later.version != record.version)
        #expect(later.outputFullURLs == record.outputFullURLs)
        #expect(try Fixtures.record(value: 73).version != record.version)
    }

    @Test("Reformatted bytes state the same version, and an added id changes no digest")
    func formattingEntersNoVersion() throws {
        let record = try Fixtures.record()
        let tree = try JSONSerialization.jsonObject(with: record.json)
        let reformatted = try ExchangeRecord(validating: JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted]))
        #expect(reformatted == record)
        try reformatted.verifyVersion(in: Fixtures.identityScope)

        let withID = try Fixtures.json(of: record, changing: "Provenance") { $0["id"] = "not-in-the-digest" }
        try ExchangeRecord(validating: withID).verifyVersion(in: Fixtures.identityScope)
    }

    @Test("A changed decimal lexeme keeps the key's shape but does not recompute")
    func decimalLexemeEntersTheDigest() throws {
        let record = try Fixtures.record()
        let lexeme = String(decoding: record.json, as: UTF8.self).replacingOccurrences(of: #""value":72"#, with: #""value":72.0"#)
        let changed = try ExchangeRecord(validating: Data(lexeme.utf8))
        #expect(changed.version == record.version)
        #expect(throws: ExchangeGraphError.invalidRecordVersion) {
            try changed.verifyVersion(in: Fixtures.identityScope)
        }
    }

    @Test("A grove-record-version that differs from the entry key is refused")
    func recordVersionExtensionMustMatch() throws {
        let record = try Fixtures.record()
        let other = try Fixtures.record(value: 73)
        let tampered = try Fixtures.json(of: record, changing: "Provenance") { provenance in
            var extensions = provenance["extension"] as? [[String: Any]] ?? []
            var identifier = extensions[0]["valueIdentifier"] as? [String: Any] ?? [:]
            identifier["value"] = other.version.identifier.identifier.value
            extensions[0]["valueIdentifier"] = identifier
            provenance["extension"] = extensions
        }
        #expect {
            try ExchangeRecord(validating: tampered)
        } throws: { error in
            (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.record-version-extension"
        }
    }

    @Test("A retraction Provenance carrying grove-record-version is refused")
    func retractionCarriesNoRecordVersionExtension() throws {
        let stated = try #require(try Fixtures.resources(of: Fixtures.record()).first { $0["resourceType"] as? String == "Provenance" }?["extension"])
        let tampered = try Fixtures.json(of: Fixtures.retraction(), changing: "Provenance") { $0["extension"] = stated }
        #expect {
            try ExchangeRecord(validating: tampered)
        } throws: { error in
            (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.record-version-extension"
        }
    }

    @Test("A Bundle states Bundle.timestamp, and every lifecycle Provenance when its record occurred")
    func recordTimes() throws {
        for record in [try Fixtures.record(), try Fixtures.retraction()] {
            var root = try #require(try JSONSerialization.jsonObject(with: record.json) as? [String: Any])
            root["timestamp"] = nil
            let noOccurrence = try Fixtures.json(of: record, changing: "Provenance") { provenance in
                provenance["occurredDateTime"] = nil
                provenance["occurredPeriod"] = nil
            }
            for tampered in [try JSONSerialization.data(withJSONObject: root), noOccurrence] {
                #expect {
                    try ExchangeRecord(validating: tampered)
                } throws: { error in
                    (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.record-times"
                }
            }
        }
    }

    @Test("A retraction carries its key on the entry alone, and that key ignores its times")
    func retractionKey() throws {
        let record = try Fixtures.retraction()
        #expect(record.kind == .retraction)
        #expect(record.version.identifier.role == .recordRetraction)
        #expect(record.outputFullURLs.isEmpty)
        let provenance = try #require(try Fixtures.resources(of: record).first { $0["resourceType"] as? String == "Provenance" })
        #expect(provenance["extension"] == nil)
        try record.verifyVersion(in: Fixtures.identityScope)

        let reported = try Fixtures.retraction(occurred: .period(start: nil, end: Fixtures.instant), at: Fixtures.instant.addingTimeInterval(60))
        #expect(reported.version == record.version)
    }

    @Test("A retraction names the shared application Device literally, with its host")
    func retractionStatesItsAssembler() throws {
        let record = try Fixtures.retraction()
        let resources = try Fixtures.resources(of: record)
        #expect(resources.compactMap { $0["resourceType"] as? String }.sorted() == ["Device", "Device", "Provenance"])
        let active = try Fixtures.record()
        #expect(record.sharedNodeFullURLs == active.sharedNodeFullURLs)
    }

    @Test("A retraction read back from bytes states no subject, as nothing in it does")
    func retractionSubject() throws {
        let record = try Fixtures.retraction()
        #expect(record.subject == (try Fixtures.subject()).identifier)
        #expect(try ExchangeRecord(validating: record.json).subject == nil)
        #expect(try ExchangeRecord(validating: Fixtures.record().json).subject == (try Fixtures.subject()).identifier)
    }

    #if canImport(ObjectiveC)
    /// A read-back's Foundation temporaries would otherwise stay in the caller's pool until a whole drain finishes: ~15 KB
    /// per record here without the read-back's own pool, nothing with it. Live heap bytes are process-wide and other suites
    /// run concurrently, so the smallest growth over two rounds is held to a bound well between the two.
    @Test(
        "Reading a record back leaves no Foundation temporaries in the caller's autorelease pool",
        .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Process-wide heap measurement is too noisy on shared CI runners")
    )
    func readBackDrainsItsOwnTemporaries() throws {
        func liveHeapBytes() -> Int {
            var statistics = malloc_statistics_t()
            malloc_zone_statistics(nil, &statistics)
            return Int(statistics.size_in_use)
        }
        var device = RecordingDevice()
        device.name = "Apple Watch"
        device.manufacturer = "Apple Inc."
        device.model = "Watch"
        device.hardwareVersion = "Watch7,1"
        device.softwareVersion = "11.0"
        let assembler = try Fixtures.assembler(studies: [Fixtures.enrollment()])
        let stored = try Fixtures.record(recordingDevice: device, assembler: assembler).json
        let iterations = 300
        let round = {
            try autoreleasepool {
                let before = liveHeapBytes()
                for _ in 0..<iterations {
                    _ = try ExchangeRecord(validating: stored)
                }
                return liveHeapBytes() - before
            }
        }
        _ = try round()
        let retained = min(try round(), try round())
        #expect(retained < 2 << 20, "\(retained) bytes stayed in the caller's pool over \(iterations) read-backs")
    }
    #endif

    @Test("Every content key of a record recomputes from what it carries")
    func derivedKeysRecompute() throws {
        let assembler = try Fixtures.assembler(studies: [Fixtures.enrollment()])
        var device = RecordingDevice()
        device.name = "Strap"
        let record = try Fixtures.record(recordingDevice: device, assembler: assembler)
        let graph = try ExchangeGraph(validating: record.json, kind: .active)
        try graph.validateDerivedKeys(in: Fixtures.identityScope)
    }

    @Test("A bundled Patient is a content-keyed node, and every record states it the same way")
    func bundledPatient() throws {
        let identifier = try Fixtures.subject().identifier
        let subject = Subject.bundled(identifier, Patient(identifier: [identifier.fhirIdentifier]))
        let assembler = try Fixtures.assembler(subject: subject, studies: [Fixtures.enrollment()])
        let first = try Fixtures.record(assembler: assembler)
        let second = try Fixtures.record(nativeRecordID: "record-2", assembler: assembler)
        #expect(first.subject == identifier)
        #expect(first.sharedNodeFullURLs == second.sharedNodeFullURLs)
        try ExchangeGraph(validating: first.json, kind: .active).validateDerivedKeys(in: Fixtures.identityScope)
    }

    @Test("Study nodes carry their context-snapshot Identifier, and a new revision is a new node")
    func studyNodes() throws {
        let record = try Fixtures.record(assembler: Fixtures.assembler(studies: [Fixtures.enrollment()]))
        for type in ["ResearchStudy", "ResearchSubject", "PlanDefinition"] {
            let resource = try #require(try Fixtures.resources(of: record).first { $0["resourceType"] as? String == type })
            let identifiers = try #require(resource["identifier"] as? [[String: Any]])
            let roles = identifiers.compactMap { (($0["type"] as? [String: Any])?["coding"] as? [[String: Any]])?.first?["code"] as? String }
            #expect(roles == ["context-snapshot"])
        }
        let revised = try Fixtures.record(assembler: Fixtures.assembler(studies: [Fixtures.enrollment(protocolVersion: "2.0")]))
        #expect(revised.sharedNodeFullURLs != record.sharedNodeFullURLs)
    }

    @Test("A changed host is a new host and a new application, which names it")
    func hostFoldsIntoApplication() throws {
        let record = try Fixtures.record()
        let updated = try Fixtures.record(assembler: Fixtures.assembler(operatingSystemVersion: "26.1.0"))
        #expect(updated.sharedNodeFullURLs.isDisjoint(with: record.sharedNodeFullURLs))
    }

    @Test("Records of two subjects share no snapshot, however alike their content")
    func snapshotsAreScopedToTheSubject() throws {
        let first = try Fixtures.record()
        let second = try Fixtures.record(assembler: Fixtures.assembler(subject: Fixtures.subject("participant-002")))
        #expect(first.sharedNodeFullURLs.isDisjoint(with: second.sharedNodeFullURLs))
    }

    @Test("A recording Device needs no unit: it always carries its snapshot, and its unit only with a token")
    func recordingDeviceIdentities() throws {
        var device = RecordingDevice()
        device.name = "Strap"
        let snapshotOnly = try recordingDevice(of: Fixtures.record(recordingDevice: device))
        #expect(roles(of: snapshotOnly) == ["device-snapshot"])

        device.stableUnitToken = "token"
        device.tokenScope = "org.example.writer"
        let unit = try recordingDevice(of: Fixtures.record(recordingDevice: device))
        #expect(roles(of: unit) == ["device-snapshot", "recording-device"])
    }

    @Test("A unit token needs a scope, which says who assigned it")
    func unitTokenNeedsAScope() throws {
        var device = RecordingDevice()
        device.stableUnitToken = "token"
        #expect(throws: ExchangeIdentityError.emptyComponent("recording-device.token-scope")) {
            try Fixtures.record(recordingDevice: device)
        }
    }

    @Test("A recording Device states every fact, each where the catalog maps it")
    func recordingDeviceFacts() throws {
        var device = RecordingDevice()
        device.name = "My Watch"
        device.manufacturer = "Apple"
        device.model = "Apple Watch"
        device.productType = "Watch7,1"
        device.systemName = "watchOS"
        device.systemVersion = "26.0"
        device.hardwareVersion = "hw"
        device.firmwareVersion = "fw"
        device.softwareVersion = "sw"
        device.localIdentifier = "local"
        device.udiDeviceIdentifier = "udi-di"
        device.udiProductionIdentifier = "udi-pi"
        device.serialNumber = "serial"
        let resource = try recordingDevice(of: Fixtures.record(recordingDevice: device))
        #expect(resource["manufacturer"] as? String == "Apple")
        #expect(resource["modelNumber"] as? String == "Watch7,1")
        #expect(resource["serialNumber"] as? String == "serial")
        let names = try #require(resource["deviceName"] as? [[String: Any]])
        #expect(names.compactMap { $0["type"] as? String } == ["user-friendly-name", "model-name"])
        #expect(names.compactMap { $0["name"] as? String } == ["My Watch", "Apple Watch"])
        let versions = try #require(resource["version"] as? [[String: Any]])
        #expect(versions.compactMap { $0["value"] as? String } == ["hw", "fw", "sw", "watchOS", "26.0"])
        let carrier = try #require((resource["udiCarrier"] as? [[String: Any]])?.first)
        #expect(carrier["deviceIdentifier"] as? String == "udi-di")
        let production = try #require((carrier["extension"] as? [[String: Any]])?.first)
        #expect(production["valueString"] as? String == "udi-pi")

        let identifiers = try #require(resource["identifier"] as? [[String: Any]])
        let local = try #require(identifiers.first { $0["value"] as? String == "local" })
        let coding = try #require(((local["type"] as? [String: Any])?["coding"] as? [[String: Any]])?.first)
        #expect(coding["code"] as? String == "device-local-identifier")
        #expect(coding["system"] as? String == Canonicals.groveDeviceIdentifierType.value?.url.absoluteString)
        #expect(local["system"] as? String == "https://study.example.org/fhir/NamingSystem/grove-device-local-identifier")
    }

    @Test("A source's one model is the Device's model number")
    func modelWithoutProductType() throws {
        var device = RecordingDevice()
        device.model = "HRM-2"
        let resource = try recordingDevice(of: Fixtures.record(recordingDevice: device))
        #expect(resource["modelNumber"] as? String == "HRM-2")
        #expect(resource["deviceName"] == nil)
    }

    @Test("A blank fact counts as unset")
    func blankFacts() throws {
        var device = RecordingDevice()
        device.name = " "
        device.localIdentifier = ""
        let resource = try recordingDevice(of: Fixtures.record(recordingDevice: device))
        #expect(resource["deviceName"] == nil)
        #expect(roles(of: resource) == ["device-snapshot"])
        #expect((resource["identifier"] as? [[String: Any]])?.count == 1)
    }

    @Test("Equal facts are one snapshot, and changed firmware a new one")
    func snapshotsFollowContent() throws {
        var device = RecordingDevice()
        device.firmwareVersion = "1"
        let first = try Fixtures.record(recordingDevice: device)
        let second = try Fixtures.record(nativeRecordID: "record-2", recordingDevice: device)
        device.firmwareVersion = "2"
        let updated = try Fixtures.record(nativeRecordID: "record-3", recordingDevice: device)
        #expect(first.sharedNodeFullURLs == second.sharedNodeFullURLs)
        #expect(first.sharedNodeFullURLs != updated.sharedNodeFullURLs)
    }

    private func recordingDevice(of record: ExchangeRecord) throws -> [String: Any] {
        let profile = Profile.groveRecordingDevice.value?.url.absoluteString ?? ""
        return try #require(try Fixtures.resources(of: record).first { resource in
            ((resource["meta"] as? [String: Any])?["profile"] as? [String])?.contains(profile) == true
        })
    }

    private func roles(of resource: [String: Any]) -> [String] {
        (resource["identifier"] as? [[String: Any]] ?? []).compactMap { identifier in
            let codings = (identifier["type"] as? [String: Any])?["coding"] as? [[String: Any]] ?? []
            return codings.first { $0["system"] as? String == Canonicals.identifierRoleCodeSystemValue }?["code"] as? String
        }
    }
}
