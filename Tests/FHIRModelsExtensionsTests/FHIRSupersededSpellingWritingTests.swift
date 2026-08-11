//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRModelsExtensions
import Foundation
import GroveLegacyIdentifiers
import ModelsR4
import Testing


/// Dual-write exists so an analysis pipeline keyed on the pre-Grove URLs keeps working across the
/// update. A copy that is subtly wrong is worse than none, so these check the copies are exact.
@Suite
struct FHIRSupersededSpellingWritingTests {
    private static let canonical = "https://grovealliance.org/fhir/core/StructureDefinition/sourceDevice"
    private static let legacy = "https://bdh.stanford.edu/fhir/defs/sourceDevice"
    private static let identifier = FHIRCanonicalURL(canonical, superseding: [legacy])

    private func ext(_ url: String, value: String? = nil, children: [Extension] = []) -> Extension {
        // swiftlint:disable:next force_unwrapping
        var element = Extension(url: URL(string: url)!.asFHIRURIPrimitive())
        if let value {
            element.value = .string(value.asFHIRStringPrimitive())
        }
        if !children.isEmpty {
            element.extension = children
        }
        return element
    }

    private func observation(_ extensions: [Extension]) -> Observation {
        var observation = Observation(code: CodeableConcept(), status: .init(.final))
        observation.extension = extensions
        return observation
    }

    private func urls(_ observation: Observation) -> [String] {
        (observation.extension ?? []).compactMap(\.urlString)
    }

    @Test
    func theDefaultPolicyWritesNothingExtra() {
        var subject = observation([ext(Self.canonical, value: "iPhone")])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalOnly)

        #expect(urls(subject) == [Self.canonical])
    }

    @Test
    func optingInAddsACopyUnderEverySupersededSpelling() throws {
        var subject = observation([ext(Self.canonical, value: "iPhone")])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        #expect(Set(urls(subject)) == [Self.canonical, Self.legacy])
        let copy = try #require(subject.extension?.first { $0.urlString == Self.legacy })
        #expect(copy.value?.stringValue?.value?.string == "iPhone")
    }

    /// `sourceRevision` and `metadata` build nested trees; a shallow copy would produce a legacy-named
    /// parent whose children still carried the canonical spelling — unreadable by the old pipeline.
    @Test
    func copiesAreDeepAndRewriteEveryChild() throws {
        var subject = observation([
            ext(Self.canonical, children: [
                ext(Self.canonical + "/source", children: [
                    ext(Self.canonical + "/source/bundleIdentifier", value: "org.example.app")
                ])
            ])
        ])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        let copy = try #require(subject.extension?.first { $0.urlString == Self.legacy })
        let source = try #require(copy.extension?.first)
        #expect(source.urlString == Self.legacy + "/source")
        let leaf = try #require(source.extension?.first)
        #expect(leaf.urlString == Self.legacy + "/source/bundleIdentifier")
        #expect(leaf.value?.stringValue?.value?.string == "org.example.app")
    }

    /// The canonical tree must survive the copy untouched — a reference-semantics slip here would
    /// rewrite the real extension into the legacy spelling and lose the canonical one entirely.
    @Test
    func theCanonicalTreeIsUnchanged() throws {
        var subject = observation([
            ext(Self.canonical, children: [ext(Self.canonical + "/model", value: "iPhone17,1")])
        ])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        let original = try #require(subject.extension?.first { $0.urlString == Self.canonical })
        #expect(original.extension?.first?.urlString == Self.canonical + "/model")
    }

    @Test
    func runningTwiceDoesNotStackDuplicates() {
        var subject = observation([ext(Self.canonical, value: "iPhone")])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)
        let afterFirst = urls(subject).sorted()
        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        #expect(urls(subject).sorted() == afterFirst)
        #expect(urls(subject).count == 2)
    }

    /// A resource that already carried the legacy spelling gets it rebuilt from the canonical value,
    /// not left at whatever a previous version wrote.
    @Test
    func anExistingLegacyCopyIsReplacedNotKept() throws {
        var subject = observation([
            ext(Self.canonical, value: "current"),
            ext(Self.legacy, value: "stale")
        ])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        let copy = try #require(subject.extension?.first { $0.urlString == Self.legacy })
        #expect(copy.value?.stringValue?.value?.string == "current")
        #expect(urls(subject).count == 2)
    }

    /// Top-level matching is exact on purpose: a prefix match would treat a different extension that
    /// merely starts with the same string as the one being mirrored.
    @Test
    func aDifferentExtensionSharingAPrefixIsNotMirrored() {
        let sibling = Self.canonical + "V2"
        var subject = observation([ext(sibling, value: "other")])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        #expect(urls(subject) == [sibling])
    }

    @Test
    func unrelatedExtensionsAreLeftAlone() {
        let other = "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden"
        var subject = observation([ext(Self.canonical, value: "iPhone"), ext(other, value: "true")])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        #expect(Set(urls(subject)) == [Self.canonical, Self.legacy, other])
    }

    @Test
    func anIdentifierWithNoHistoryIsANoOp() {
        let fresh = FHIRCanonicalURL("https://grovealliance.org/fhir/core/StructureDefinition/brandNew")
        var subject = observation([ext(fresh.canonical, value: "x")])

        subject.writeSupersededSpellings(of: [fresh], policy: .canonicalAndSuperseded)

        #expect(urls(subject) == [fresh.canonical])
    }

    @Test
    func aResourceWithNoExtensionsIsUntouched() {
        var subject = Observation(code: CodeableConcept(), status: .init(.final))

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        #expect(subject.extension == nil)
    }

    @Test
    func theShippedDefaultIsCanonicalOnly() {
        #expect(FHIRWritePolicy.default == .canonicalOnly)
    }
}
