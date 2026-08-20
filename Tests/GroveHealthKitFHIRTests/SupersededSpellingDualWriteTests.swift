//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
@testable import GroveHealthKitFHIR
import GroveLegacyIdentifiers
import HealthKit
import ModelsR4
import Testing


/// The migration guide tells a consumer that setting the policy is enough — no call site has to name
/// the identifiers. These convert a real sample and check the copies actually land, which is the only
/// way to catch a writer that bypasses the shared `append` and so never dual-writes.
///
/// Serialized because `FHIRWritePolicy.default` is process-wide state.
@Suite(.serialized)
struct SupersededSpellingDualWriteTests {
    private func stepCountObservation() throws -> Observation {
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 17),
            start: .now,
            end: .now,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        let resource = try sample.resource()
        return try #require(resource.get(if: Observation.self))
    }

    private func spellings(_ observation: Observation) -> Set<String> {
        Set((observation.extension ?? []).compactMap { $0.url.value?.url.absoluteString })
    }

    private func spellings(in element: Extension) -> [String] {
        let ownSpelling: [String] = if let spelling = element.url.value?.url.absoluteString {
            [spelling]
        } else {
            []
        }
        return ownSpelling + (element.extension ?? []).flatMap { spellings(in: $0) }
    }

    private func withPolicy(_ policy: FHIRWritePolicy, _ body: () throws -> Void) rethrows {
        let previous = FHIRWritePolicy.default
        FHIRWritePolicy.default = policy
        defer { FHIRWritePolicy.default = previous }
        try body()
    }

    /// The shipped behaviour: a fresh install emits the current spelling and nothing else.
    @Test
    func theDefaultEmitsOnlyTheCanonicalSpelling() throws {
        try withPolicy(.canonicalOnly) {
            let urls = spellings(try stepCountObservation())
            for retired in SupersededFHIRURLs.sourceDevice + SupersededFHIRURLs.sourceRevision + SupersededFHIRURLs.metadata {
                #expect(!urls.contains(retired), "\(retired) must not be written by default")
            }
            #expect(urls.contains(FHIRExtensionURL.sourceRevision.url.absoluteString))
        }
    }

    /// Opting in has to reach every identifier the conversion writes, not just the ones a call site
    /// happened to list — that is the whole point of hooking the shared append.
    @Test
    func optingInMirrorsEveryReproducibleIdentifierTheConversionWrites() throws {
        try withPolicy(.canonicalAndSuperseded) {
            let urls = spellings(try stepCountObservation())
            for identifier in [FHIRExtensionURL.sourceRevision, .metadata] {
                #expect(urls.contains(identifier.url.absoluteString), "\(identifier.url) lost its canonical spelling")
                for retired in identifier.superseded {
                    if SupersededFHIRURLs.notReproducibleByDualWrite.contains(retired.absoluteString) {
                        #expect(!urls.contains(retired.absoluteString), "\(retired) must not be reproduced with a changed payload")
                    } else {
                        #expect(urls.contains(retired.absoluteString), "\(retired) was not mirrored on opt-in")
                    }
                }
            }
        }
    }

    /// A mirrored copy is only useful if it carries the same payload the canonical one does.
    @Test
    func theMirroredCopyCarriesTheSameNestedPayload() throws {
        try withPolicy(.canonicalAndSuperseded) {
            let observation = try stepCountObservation()
            let canonical = try #require(observation.extensions(for: FHIRExtensionURL.sourceRevision).first)
            let retiredSpelling = try #require(FHIRExtensionURL.sourceRevision.superseded.first)
            let copy = try #require(
                (observation.extension ?? []).first { $0.url.value?.url.absoluteString == retiredSpelling.absoluteString }
            )

            let canonicalSpelling = FHIRExtensionURL.sourceRevision.url.absoluteString
            let canonicalTreeSpellings = spellings(in: canonical)
            let expectedRetiredTreeSpellings = canonicalTreeSpellings.map { spelling in
                retiredSpelling.absoluteString + String(spelling.dropFirst(canonicalSpelling.count))
            }
            let retiredTreeSpellings = spellings(in: copy)

            #expect(canonicalTreeSpellings.allSatisfy { $0.hasPrefix(canonicalSpelling) })
            #expect(retiredTreeSpellings == expectedRetiredTreeSpellings)
            #expect(Set(retiredTreeSpellings).count == retiredTreeSpellings.count)
            #expect(copy.value == canonical.value)
        }
    }

    /// Converting twice under the policy must not stack duplicates.
    @Test
    func mirroringIsIdempotent() throws {
        try withPolicy(.canonicalAndSuperseded) {
            var observation = try stepCountObservation()
            let before = (observation.extension ?? []).count
            observation.writeSupersededSpellings(of: FHIRSupersessionRegistry.all)
            #expect((observation.extension ?? []).count == before)
        }
    }
}
