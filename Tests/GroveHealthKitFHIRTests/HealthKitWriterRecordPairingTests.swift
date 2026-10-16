//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
import Testing


/// The guide's producer validator rejects an entry claiming a HealthKit profile whose writer-record identity travels
/// without its version, or the reverse ("adapter requires writer-record identity and version together",
/// Scripts/producer_validation/profiles.py; healthkit-writer-record-1). The guide registers no code for the check, so
/// Grove's validator cannot report it under one, and this suite mirrors it over every golden instead.
@Suite
struct HealthKitWriterRecordPairingTests {
    /// The fullUrl of each entry of `bundle` claiming a HealthKit profile whose writer-record identities and versions do
    /// not pair one to one.
    static func unpairedWriterRecords(in bundle: LosslessJSONValue) -> [String] {
        let version = Canonicals.writerRecordVersion.value?.url.absoluteString
        return (bundle["entry"]?.elements ?? []).compactMap { entry in
            let resource = entry["resource"]
            let profiles = resource?["meta"]?["profile"]?.elements ?? []
            guard profiles.contains(where: { $0.text?.hasPrefix("https://grovealliance.org/fhir/healthkit/StructureDefinition/") == true }) else {
                return nil
            }
            let identities = (resource?["identifier"]?.elements ?? []).filter { identifier in
                identifier["type"]?["coding"]?.elements?.contains { $0["code"]?.text == "writer-record" } == true
            }
            let versions = (resource?["extension"]?.elements ?? []).filter { $0["url"]?.text == version }
            return identities.count == versions.count && identities.count <= 1 ? nil : entry["fullUrl"]?.text ?? "an entry without fullUrl"
        }
    }

    @Test("Every HealthKit-profiled entry of every golden carries a writer-record identity exactly when it carries its version")
    func goldensPairWriterRecords() throws {
        let names = GoldenStore.resources.names(withExtension: "json").subtracting([GoldenStore.outlinesName])
        #expect(!names.isEmpty)
        for name in names.sorted() {
            let unpaired = Self.unpairedWriterRecords(in: try LosslessJSONValue(parsing: GoldenStore.data(named: name)))
            #expect(unpaired.isEmpty, "\(name): \(unpaired)")
        }
    }

    @Test("The mirror finds an identity without its version, a version without its identity, and two pairs")
    func mirrorFindsUnpairedEntries() throws {
        func bundle(identities: Int, versions: Int, profile: String = "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-observation") throws -> LosslessJSONValue {
            let identifier = #"{"type":{"coding":[{"code":"writer-record"}]}}"#
            let version = #"{"url":"https://grovealliance.org/fhir/mobile/StructureDefinition/grove-writer-record-version"}"#
            let identifiers = Array(repeating: identifier, count: identities).joined(separator: ",")
            let extensions = Array(repeating: version, count: versions).joined(separator: ",")
            let resource = #"{"meta":{"profile":["\#(profile)"]},"identifier":[\#(identifiers)],"extension":[\#(extensions)]}"#
            return try LosslessJSONValue(parsing: Data(#"{"entry":[{"fullUrl":"urn:uuid:1","resource":\#(resource)}]}"#.utf8))
        }
        #expect(Self.unpairedWriterRecords(in: try bundle(identities: 0, versions: 0)).isEmpty)
        #expect(Self.unpairedWriterRecords(in: try bundle(identities: 1, versions: 1)).isEmpty)
        #expect(Self.unpairedWriterRecords(in: try bundle(identities: 1, versions: 0)) == ["urn:uuid:1"])
        #expect(Self.unpairedWriterRecords(in: try bundle(identities: 0, versions: 1)) == ["urn:uuid:1"])
        #expect(Self.unpairedWriterRecords(in: try bundle(identities: 2, versions: 2)) == ["urn:uuid:1"])
        let shared = "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-heart-rate"
        #expect(Self.unpairedWriterRecords(in: try bundle(identities: 1, versions: 0, profile: shared)).isEmpty, "only HealthKit profiles pair")
    }
}

#endif
