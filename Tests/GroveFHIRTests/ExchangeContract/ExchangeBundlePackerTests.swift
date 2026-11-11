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


/// A literal reference a test adds to a packed Bundle, in `element` of the entry at `referrer`, or in a
/// `workflow-supportingInfo` extension when `element` is `extension`.
private struct AddedReference {
    let referrer: String
    let element: String
    let target: String

    /// `graph`'s JSON with this reference added.
    func applied(to graph: ExchangeGraph) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: graph.json) as? [String: Any])
        var entries = try #require(root["entry"] as? [[String: Any]])
        let index = try #require(entries.firstIndex { $0["fullUrl"] as? String == referrer })
        var resource = try #require(entries[index]["resource"] as? [String: Any])
        let reference: [String: Any] = ["reference": target]
        let item: [String: Any] = element == "extension"
            ? ["url": "http://hl7.org/fhir/StructureDefinition/workflow-supportingInfo", "valueReference": reference]
            : reference
        resource[element] = (resource[element] as? [[String: Any]] ?? []) + [item]
        entries[index]["resource"] = resource
        root["entry"] = entries
        return try JSONSerialization.data(withJSONObject: root)
    }
}


@Suite("Exchange Bundle packer")
struct ExchangeBundlePackerTests {
    private typealias Fixtures = ExchangeRecordFixtures

    @Test("Records share one entry per shared node, and each keeps its version")
    func dedupesSharedNodes() throws {
        let assembler = try Fixtures.assembler(studies: [Fixtures.enrollment()])
        var device = RecordingDevice()
        device.name = "Strap"
        let records = try (1...3).map { try Fixtures.record(nativeRecordID: "record-\($0)", recordingDevice: device, assembler: assembler) }
        var packer = ExchangeBundlePacker(kind: .active)
        for record in records {
            #expect(try packer.add(record) == .added)
        }
        #expect(packer.recordCount == 3)
        let graph = try packer.bundle(packedAt: Fixtures.instant)
        let sharedNodes = records[0].sharedNodeFullURLs
        #expect(graph.bundle.entry?.count == sharedNodes.count + 3 * 2)
        let unpacked = try graph.records()
        #expect(unpacked.map(\.version) == records.map(\.version))
        #expect(unpacked.map(\.sharedNodeFullURLs) == records.map(\.sharedNodeFullURLs))
        for record in unpacked {
            try record.verifyVersion(in: Fixtures.identityScope)
        }
    }

    @Test("Packing states the packing instant and the transport id, and changes no record")
    func bundleHeader() throws {
        let record = try Fixtures.record()
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(record)
        let transport = try BusinessIdentifier(system: IdentifierSystem("https://study.example.org/upload"), value: "upload-1")
        let later = Fixtures.instant.addingTimeInterval(3_600)
        let graph = try packer.bundle(packedAt: later, transportIdentifier: transport)
        #expect(graph.transportIdentifier == transport)
        #expect(graph.bundle.timestamp?.value?.description == ExchangeInstant.utcLexeme(later))
        #expect(try graph.records() == [record])
    }

    @Test("A packed Bundle's bytes are canonical")
    func bundleIsCanonical() throws {
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(Fixtures.record())
        _ = try packer.add(Fixtures.record(nativeRecordID: "record-2"))
        let graph = try packer.bundle(packedAt: Fixtures.instant)
        #expect(try LosslessJSONValue(parsing: graph.json).canonicalBytes() == graph.json)
    }

    @Test("The same version is a duplicate, and adds nothing")
    func duplicateVersion() throws {
        let record = try Fixtures.record()
        var packer = ExchangeBundlePacker(kind: .active)
        #expect(try packer.add(record) == .added)
        let byteCount = packer.byteCount
        #expect(try packer.add(record) == .duplicate)
        #expect(packer.recordCount == 1)
        #expect(packer.byteCount == byteCount)
    }

    @Test("A duplicate of a packed record is reported even once the packer is full")
    func duplicateOfFullPacker() throws {
        let record = try Fixtures.record()
        var packer = ExchangeBundlePacker(kind: .active, maximumRecords: 1)
        _ = try packer.add(record)
        #expect(packer.isFull)
        #expect(try packer.add(record) == .duplicate)
    }

    @Test("The same version stating an entry the Bundle doesn't hold goes into the next Bundle")
    func sameVersionWithANewEntryIsDeferred() throws {
        // A changed enrollment is a new ResearchSubject, which stays outside the record version.
        let packed = try Fixtures.record(assembler: Fixtures.assembler(studies: [Fixtures.enrollment()]))
        let reenrolled = try Fixtures.record(
            assembler: Fixtures.assembler(studies: [Fixtures.enrollment(enrollment: "enrollment-2")])
        )
        #expect(reenrolled.version == packed.version)
        #expect(reenrolled.sharedNodeFullURLs != packed.sharedNodeFullURLs)
        var packer = ExchangeBundlePacker(kind: .active)
        #expect(try packer.add(packed) == .added)
        let byteCount = packer.byteCount
        #expect(try packer.add(reenrolled) == .deferred)
        #expect(packer.recordCount == 1)
        #expect(packer.byteCount == byteCount)
        var next = ExchangeBundlePacker(kind: .active)
        #expect(try next.add(reenrolled) == .added)
        let records = try packer.bundle(packedAt: Fixtures.instant).records() + next.bundle(packedAt: Fixtures.instant).records()
        #expect(records.map(\.version) == [packed.version, packed.version])
        #expect(records.map(\.json) == [packed.json, reenrolled.json])
    }

    @Test("A second version of a packed source record is deferred")
    func secondVersionIsDeferred() throws {
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(Fixtures.record())
        #expect(try packer.add(Fixtures.record(at: Fixtures.instant.addingTimeInterval(1))) == .deferred)
        #expect(packer.recordCount == 1)
    }

    @Test("A record past either cap is deferred from a non-empty packer")
    func capsDefer() throws {
        var byRecords = ExchangeBundlePacker(kind: .active, maximumRecords: 1)
        #expect(!byRecords.isFull)
        #expect(try byRecords.add(Fixtures.record()) == .added)
        #expect(byRecords.isFull)
        #expect(try byRecords.add(Fixtures.record(nativeRecordID: "record-2")) == .deferred)

        let first = try Fixtures.record()
        var unbounded = ExchangeBundlePacker(kind: .active)
        _ = try unbounded.add(first)
        var byBytes = ExchangeBundlePacker(kind: .active, maximumBytes: unbounded.byteCount + 1)
        #expect(try byBytes.add(first) == .added)
        #expect(!byBytes.isFull)
        #expect(try byBytes.add(Fixtures.record(nativeRecordID: "record-2")) == .deferred)
        #expect(byBytes.recordCount == 1)
    }

    @Test("A cap counts only what a record adds: its shared nodes may already be packed")
    func capCountsNewEntries() throws {
        let first = try Fixtures.record()
        let second = try Fixtures.record(nativeRecordID: "record-2")
        var unbounded = ExchangeBundlePacker(kind: .active)
        _ = try unbounded.add(first)
        _ = try unbounded.add(second)
        var packer = ExchangeBundlePacker(kind: .active, maximumBytes: unbounded.byteCount)
        _ = try packer.add(first)
        #expect(try packer.add(second) == .added)
        #expect(packer.byteCount == unbounded.byteCount)
        #expect(packer.isFull)
    }

    @Test("An empty packer of the record's kind admits any one record, over the byte cap too")
    func emptyPackerAdmitsAnyRecord() throws {
        var packer = ExchangeBundlePacker(kind: .active, maximumBytes: 1)
        #expect(try packer.add(Fixtures.record()) == .added)
        #expect(packer.isFull)
        #expect(try packer.bundle(packedAt: Fixtures.instant).records().count == 1)
    }

    @Test("Other tokens under a packed fullUrl fail closed")
    func conflictingNode() throws {
        let record = try Fixtures.record()
        let tampered = try Fixtures.json(of: Fixtures.record(nativeRecordID: "record-2"), changing: "Device") { $0["manufacturer"] = "Another" }
        let conflicting = try ExchangeRecord(validating: tampered)
        let device = try #require(conflicting.entries.first { record.sharedNodeFullURLs.contains($0.fullURL) })
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(record)
        #expect(throws: ExchangeBundlePacker.Failure.conflictingNode(fullURL: device.fullURL)) {
            _ = try packer.add(conflicting)
        }
    }

    @Test("Other tokens under a packed record version fail closed, as an altered retry")
    func alteredRetry() throws {
        let record = try Fixtures.record()
        let lexeme = String(decoding: record.json, as: UTF8.self).replacingOccurrences(of: #""value":72"#, with: #""value":72.0"#)
        let altered = try ExchangeRecord(validating: Data(lexeme.utf8))
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(record)
        #expect(throws: ExchangeBundlePacker.Failure.conflictingNode(fullURL: record.outputFullURLs[0])) {
            _ = try packer.add(altered)
        }
    }

    @Test("Active and retraction records never mix")
    func mixedKinds() throws {
        var active = ExchangeBundlePacker(kind: .active)
        #expect(throws: ExchangeBundlePacker.Failure.mixedKinds) {
            _ = try active.add(Fixtures.retraction())
        }
        var retraction = ExchangeBundlePacker(kind: .retraction)
        #expect(throws: ExchangeBundlePacker.Failure.mixedKinds) {
            _ = try retraction.add(Fixtures.record())
        }
    }

    @Test("Records of another subject are refused, retractions too")
    func mixedSubjects() throws {
        let other = try Fixtures.assembler(subject: Fixtures.subject("participant-002"))
        var active = ExchangeBundlePacker(kind: .active)
        _ = try active.add(Fixtures.record())
        #expect(throws: ExchangeBundlePacker.Failure.mixedSubjects) {
            _ = try active.add(Fixtures.record(nativeRecordID: "record-2", assembler: other))
        }
        var retraction = ExchangeBundlePacker(kind: .retraction)
        _ = try retraction.add(Fixtures.retraction())
        #expect(throws: ExchangeBundlePacker.Failure.mixedSubjects) {
            _ = try retraction.add(Fixtures.retraction(nativeRecordID: "record-2", assembler: other))
        }
    }

    @Test("One participant's enrolled records pack, whichever Patient snapshot or logical reference names them")
    func studyContextFollowsTheSubjectNotItsReference() throws {
        func bundled(bornOn date: String) throws -> Subject {
            var patient = Patient()
            patient.birthDate = FHIRPrimitive(try FHIRDate(date))
            return .bundled(try Fixtures.subject().identifier, patient)
        }
        let subjects = [try bundled(bornOn: "1980-01-01"), try bundled(bornOn: "1980-01-02"), try Fixtures.subject()]
        var packer = ExchangeBundlePacker(kind: .active)
        for (index, subject) in subjects.enumerated() {
            let assembler = try Fixtures.assembler(subject: subject, studies: [Fixtures.enrollment()])
            #expect(try packer.add(Fixtures.record(nativeRecordID: "record-\(index)", assembler: assembler)) == .added)
        }
        let records = try packer.bundle(packedAt: Fixtures.instant).records()
        #expect(records.count == subjects.count)
        #expect(Set(records.map(\.subject)) == [try Fixtures.subject().identifier])
    }

    @Test("A literal reference to an output of another record is refused")
    func crossRecordLiteralReference() throws {
        let first = try Fixtures.record()
        let second = try Fixtures.record(nativeRecordID: "record-2")
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(first)
        _ = try packer.add(second)
        var root = try #require(try JSONSerialization.jsonObject(with: packer.bundle(packedAt: Fixtures.instant).json) as? [String: Any])
        var entries = try #require(root["entry"] as? [[String: Any]])
        let index = try #require(entries.firstIndex { $0["fullUrl"] as? String == second.outputFullURLs.first })
        var output = try #require(entries[index]["resource"] as? [String: Any])
        output["derivedFrom"] = [["reference": try #require(first.outputFullURLs.first)]]
        entries[index]["resource"] = output
        root["entry"] = entries
        let tampered = try JSONSerialization.data(withJSONObject: root)
        #expect {
            try ExchangeGraph(validating: tampered, kind: .active)
        } throws: { error in
            (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.cross-record-reference"
        }
    }

    @Test("No literal reference reaches a lifecycle Provenance, not even its own record's")
    func provenanceLiteralReference() throws {
        let first = try Fixtures.record()
        let second = try Fixtures.record(nativeRecordID: "record-2")
        var packer = ExchangeBundlePacker(kind: .active)
        _ = try packer.add(first)
        _ = try packer.add(second)
        let graph = try packer.bundle(packedAt: Fixtures.instant)
        let output = try #require(second.outputFullURLs.first)
        let recordEntries = Set([first.version.fullURL, second.version.fullURL] + first.outputFullURLs + second.outputFullURLs)
        let shared = try #require(
            graph.bundle.entry?.compactMap { $0.fullUrl?.value?.url.absoluteString }.first { !recordEntries.contains($0) }
        )
        let references = [
            AddedReference(referrer: output, element: "extension", target: first.version.fullURL),
            AddedReference(referrer: output, element: "basedOn", target: first.version.fullURL),
            AddedReference(referrer: output, element: "extension", target: second.version.fullURL),
            AddedReference(referrer: second.version.fullURL, element: "extension", target: first.version.fullURL),
            AddedReference(referrer: shared, element: "extension", target: first.version.fullURL)
        ]
        for reference in references {
            let tampered = try reference.applied(to: graph)
            #expect {
                try ExchangeGraph(validating: tampered, kind: .active)
            } throws: { error in
                (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.cross-record-reference"
            }
        }
    }

    @Test("No literal reference reaches a retraction Provenance")
    func retractionProvenanceLiteralReference() throws {
        let first = try Fixtures.retraction()
        let second = try Fixtures.retraction(nativeRecordID: "record-2")
        var packer = ExchangeBundlePacker(kind: .retraction)
        _ = try packer.add(first)
        _ = try packer.add(second)
        let graph = try packer.bundle(packedAt: Fixtures.instant)
        let device = try #require(graph.bundle.entry?.first { entry in
            if case .device? = entry.resource { true } else { false }
        }?.fullUrl?.value?.url.absoluteString)
        for referrer in [second.version.fullURL, device] {
            let tampered = try AddedReference(referrer: referrer, element: "extension", target: first.version.fullURL).applied(to: graph)
            #expect {
                try ExchangeGraph(validating: tampered, kind: .retraction)
            } throws: { error in
                (error as? ExchangeGraphError)?.diagnostic.code == "mobile-exchange.cross-record-reference"
            }
        }
    }

    @Test("A retraction Bundle holds N records, and the first accepted of a source record wins")
    func retractions() throws {
        let first = try Fixtures.retraction()
        let reported = try Fixtures.retraction(occurred: .period(start: nil, end: Fixtures.instant), at: Fixtures.instant.addingTimeInterval(60))
        let second = try Fixtures.retraction(nativeRecordID: "record-2")
        var packer = ExchangeBundlePacker(kind: .retraction)
        #expect(try packer.add(first) == .added)
        #expect(try packer.add(reported) == .duplicate)
        #expect(try packer.add(second) == .added)
        let graph = try packer.bundle(packedAt: Fixtures.instant)
        #expect(graph.kind == .retraction)
        let records = try graph.records()
        #expect(records.map(\.version) == [first.version, second.version])
        // The two records share the application Device and its host.
        #expect(graph.bundle.entry?.count == 4)
        #expect(records[0].json == first.json)
    }

    @Test("An empty packer has no Bundle to state")
    func emptyBundle() throws {
        #expect(throws: ExchangeGraphError.ruleViolation(.mobileExchangeEntryRequired)) {
            _ = try ExchangeBundlePacker(kind: .active).bundle(packedAt: Fixtures.instant)
        }
    }

    @Test("A Bundle of up to the default cap is valid", .timeLimit(.minutes(1)))
    func manyRecords() throws {
        let assembler = try Fixtures.assembler(studies: [Fixtures.enrollment()])
        var packer = ExchangeBundlePacker(kind: .active)
        for index in 0..<500 {
            _ = try packer.add(Fixtures.record(nativeRecordID: "record-\(index)", assembler: assembler))
        }
        let graph = try packer.bundle(packedAt: Fixtures.instant)
        #expect(try graph.records().count == 500)
    }
}
