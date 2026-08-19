//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import GroveFHIR
@testable import GroveHealthKitFHIR
import GroveLegacyIdentifiers
import HealthKit
import ModelsR4
import Testing


/// The migration guide tells a consumer that setting the policy is enough — no call site has to name
/// the identifiers. These convert a real sample and check what actually lands, which is the only way
/// to catch a writer that bypasses the shared `append`, or a declaration that quietly lost its history.
///
/// Serialized because `FHIRWritePolicy.default` is process-wide state.
@Suite(.serialized)
struct SupersededSpellingDualWriteTests {
    /// Every identifier the HealthKit conversion writes that has a retired spelling to resolve.
    private static let published: [FHIRExtensionURL] = [.metadata, .hkSampleId]

    private func stepCountObservation() throws -> Observation {
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 17),
            start: .now,
            end: .now,
            // WasUserEntered is routed to grove-recording-method; the external UUID
            // keeps the metadata envelope populated for the dual-write checks.
            metadata: [HKMetadataKeyWasUserEntered: true, HKMetadataKeyExternalUUID: "test-uuid"]
        )
        let resource = try sample.resource(subject: Reference(reference: "Patient/example"))
        return try #require(resource.get(if: Observation.self))
    }

    private func spellings(_ observation: Observation) -> Set<String> {
        Set((observation.extension ?? []).compactMap { $0.url.value?.url.absoluteString })
    }

    private func withPolicy(_ policy: FHIRWritePolicy, _ body: () throws -> Void) rethrows {
        let previous = FHIRWritePolicy.default
        FHIRWritePolicy.default = policy
        defer { FHIRWritePolicy.default = previous }
        try body()
    }

    /// Naming the declarations is what gives this reach: dropping one stops the suite compiling, and
    /// emptying its history fails here instead of silently in a consumer's pipeline.
    @Test("written identifiers keep the spellings they published", arguments: Self.published)
    func writtenIdentifiersKeepTheirRetiredSpellings(identifier: FHIRExtensionURL) {
        #expect(identifier.url.absoluteString.hasPrefix("https://grovealliance.org/fhir/core/StructureDefinition/"))
        #expect(!identifier.superseded.isEmpty)
        #expect(FHIRSupersessionRegistry.all.contains { $0.canonical == identifier.url.absoluteString })
    }

    /// The shipped behaviour: a fresh install emits the current spelling and nothing else.
    @Test
    func theDefaultEmitsOnlyTheCanonicalSpelling() throws {
        try withPolicy(.canonicalOnly) {
            let urls = spellings(try stepCountObservation())
            for retired in Self.published.flatMap(\.superseded) {
                #expect(!urls.contains(retired.absoluteString), "\(retired) must not be written by default")
            }
            #expect(urls.contains(FHIRExtensionURL.metadata.url.absoluteString))
        }
    }

    /// Metadata is the one identifier this conversion writes that retired a spelling, and its payload
    /// changed shape at the same time — the key moved out of the url, and the routed entries left the
    /// envelope. So opting in adds nothing here: a copy would be an encoding no 0.4 pipeline can read.
    @Test
    func optingInDoesNotFabricateTheRetiredMetadataEnvelope() throws {
        try withPolicy(.canonicalAndSuperseded) {
            let urls = spellings(try stepCountObservation())
            for retired in FHIRExtensionURL.metadata.superseded {
                #expect(SupersededFHIRURLs.notReproducibleByDualWrite.contains(retired.absoluteString))
                #expect(!urls.contains(retired.absoluteString), "\(retired) cannot be rebuilt from today's payload")
            }
        }
    }

    /// Opting in is a compatibility copy, never a rewrite: whatever the policy, the canonical resource
    /// a consumer reads today is the same one.
    @Test
    func optingInLeavesTheCanonicalResourceUntouched() throws {
        var canonicalOnly: Observation?
        try withPolicy(.canonicalOnly) { canonicalOnly = try stepCountObservation() }
        var dualWritten: Observation?
        try withPolicy(.canonicalAndSuperseded) { dualWritten = try stepCountObservation() }

        let before = try #require(canonicalOnly).extensions(for: FHIRExtensionURL.metadata)
        let after = try #require(dualWritten).extensions(for: FHIRExtensionURL.metadata)
        #expect(!before.isEmpty)
        #expect(before == after)
    }

    /// The half of the contract that survives a shape change: a resource written before the rename
    /// still resolves, whichever spelling it carries.
    @Test
    func aResourceWrittenBeforeTheRenameStillResolves() throws {
        var observation = try stepCountObservation()
        let retired = try #require(FHIRExtensionURL.metadata.superseded.first)
        let canonical = observation.extensions(for: FHIRExtensionURL.metadata)
        observation.extension = canonical.map { entry in
            var copy = entry
            copy.url = retired.asFHIRURIPrimitive()
            return copy
        }

        let found = observation.extensions(for: FHIRExtensionURL.metadata)
        #expect(found.count == canonical.count)
        #expect(!found.isEmpty)
    }
}
