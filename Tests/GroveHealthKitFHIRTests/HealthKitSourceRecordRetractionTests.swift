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
@testable import GroveHealthKitFHIR
import ModelsR4
import Testing


@Suite
struct HealthKitSourceRecordRetractionTests {
    @Test(arguments: [HealthKitSourceType.workout, .electrocardiogram])
    func deletionWithoutTheSampleRetractsAllItsOutputs(_ sourceType: HealthKitSourceType) async throws {
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: GoldenFixtures.uuid(0xE7),
            sourceType: sourceType,
            deletedAfter: nil,
            detectedAt: GoldenFixtures.conversionInstant
        )
        var inputs = ExportInputs()
        inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        let graph = try await ExporterFixtures.retraction(deletion, inputs)
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        try #require(provenance.target.count == 1)
        let target = try #require(provenance.target.first)
        #expect(target.type == nil)
        #expect(target.reference == nil)
        #expect(target.identifier == provenance.entity?.first?.what.identifier)
        #expect(try RoledIdentifier(#require(target.identifier)).role == .sourceRecord)
        let role = target.extension?.first { $0.url == Canonicals.retractionTargetRole }
        #expect(role?.value == .code("source-record".asFHIRStringPrimitive()))
        let native = target.extension?.first { $0.url == Canonicals.retractionTargetNativeIdentifier }
        guard case .identifier(let identifier)? = native?.value else {
            Issue.record("The authorized native identifier must remain on the source-record target")
            return
        }
        #expect(identifier.value?.value?.string == deletion.uuid.uuidString.lowercased())
    }
}

#endif
