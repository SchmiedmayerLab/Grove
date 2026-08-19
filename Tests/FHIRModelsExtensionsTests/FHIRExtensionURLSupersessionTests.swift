//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRModelsExtensions
import Foundation
import ModelsR4
import Testing


/// These identify extensions inside `Observation`s that have already left the device for a research
/// database. A superseded spelling has to keep resolving even after the writer is gone, and a rewrite
/// must never leave two spellings of one concept behind.
@Suite
struct FHIRExtensionURLSupersessionTests {
    /// The URL-typed form of a real declaration, so the spellings under test are the published ones.
    private static let identifier = FHIRExtensionURL(
        RetiredFHIRCanonicalURLs.sourceDevice.canonical,
        superseding: RetiredFHIRCanonicalURLs.sourceDevice.superseded
    )

    private func observation(withExtensionsAt urls: [URL]) -> Observation {
        var observation = Observation(code: CodeableConcept(), status: .init(.final))
        observation.extension = urls.map {
            Extension(url: $0.asFHIRURIPrimitive(), value: .string($0.absoluteString.asFHIRStringPrimitive()))
        }
        return observation
    }

    private func values(_ extensions: [Extension]) -> [String] {
        extensions.compactMap { $0.value?.stringValue?.value?.string }
    }

    @Test
    func findsTheCanonicalSpelling() {
        let found = observation(withExtensionsAt: [Self.identifier.url]).extensions(for: Self.identifier)
        #expect(values(found) == [Self.identifier.url.absoluteString])
    }

    @Test
    func findsASpellingWrittenBeforeTheRename() throws {
        let legacy = try #require(Self.identifier.superseded.first)
        let found = observation(withExtensionsAt: [legacy]).extensions(for: Self.identifier)
        #expect(values(found) == [legacy.absoluteString])
    }

    /// A resource carrying both was written by a newer version; the superseded copy is a compatibility
    /// duplicate, not a second value.
    @Test
    func theCanonicalSpellingWinsWhenBothArePresent() throws {
        let legacy = try #require(Self.identifier.superseded.first)
        let found = observation(withExtensionsAt: [legacy, Self.identifier.url]).extensions(for: Self.identifier)
        #expect(values(found) == [Self.identifier.url.absoluteString])
    }

    /// The bug this guards: rewriting an `Observation` that already carried the legacy spelling would
    /// otherwise leave both, so the resource would claim two different source devices.
    @Test
    func removingClearsEverySpelling() throws {
        let legacy = try #require(Self.identifier.superseded.first)
        var subject = observation(withExtensionsAt: [legacy, Self.identifier.url])

        let removed = subject.removeAllExtensions(withUrl: Self.identifier)

        #expect(removed?.count == 2)
        #expect(subject.extension == nil)
    }

    @Test
    func removingLeavesUnrelatedExtensionsAlone() throws {
        let other = try #require(URL(string: "http://example.org/other"))
        var subject = observation(withExtensionsAt: [Self.identifier.url, other])

        subject.removeAllExtensions(withUrl: Self.identifier)

        #expect(values(subject.extension ?? []) == [other.absoluteString])
    }

    /// Sub-extensions are built by appending to the base, so they only resolve under the old names if
    /// the derived URLs inherit the derived legacy spellings.
    @Test
    func derivedURLsInheritDerivedSpellings() throws {
        let derived = Self.identifier.appending(component: "manufacturer")
        let legacyBase = try #require(Self.identifier.superseded.first)

        #expect(derived.url.absoluteString == Self.identifier.url.absoluteString + "/manufacturer")
        #expect(derived.superseded.map(\.absoluteString) == [legacyBase.absoluteString + "/manufacturer"])

        let found = observation(withExtensionsAt: derived.superseded).extensions(for: derived)
        #expect(values(found) == derived.superseded.map(\.absoluteString))
    }

    @Test
    func appendingMultipleComponentsPropagatesToEverySpelling() throws {
        let derived = Self.identifier.appending(components: ["source", "bundleIdentifier"])
        let legacyBase = try #require(Self.identifier.superseded.first)

        #expect(derived.url.absoluteString.hasSuffix("/sourceDevice/source/bundleIdentifier"))
        #expect(derived.superseded.map(\.absoluteString) == [legacyBase.absoluteString + "/source/bundleIdentifier"])
    }

    @Test
    func aURLWithNoHistoryBehavesExactlyAsBefore() throws {
        let plain = FHIRExtensionURL("http://example.org/thing")
        #expect(plain.superseded.isEmpty)
        #expect(plain.allURLs.count == 1)

        var subject = observation(withExtensionsAt: [plain.url])
        subject.removeAllExtensions(withUrl: plain)
        #expect(subject.extension == nil)
    }

    /// A published URL sits under the current authority and keeps whatever was published before it
    /// readable. Parameterised over the declarations themselves: the retired ones have no writer left,
    /// so if one were dropped nothing else in the suite would notice.
    @Test("retired identifiers still resolve every spelling they published", arguments: RetiredFHIRCanonicalURLs.all)
    func retiredIdentifiersStillResolve(identifier: FHIRCanonicalURL) throws {
        #expect(identifier.canonical.hasPrefix("https://grovealliance.org/fhir/core/StructureDefinition/"))

        let published = try #require(identifier.superseded.last)
        let resource = observation(withExtensionsAt: [try #require(URL(string: published))])
        #expect(values(resource.extensions(for: identifier)) == [published])
    }
}
