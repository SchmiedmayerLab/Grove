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
/// update. A copy that is subtly wrong is worse than none, so these check that the copies are exact —
/// and that a spelling whose payload changed shape with its url gets no copy at all.
///
/// Serialized because `FHIRWritePolicy.default` is process-wide: a test that opts in would otherwise
/// race the ones asserting the shipped default.
@Suite(.serialized)
struct FHIRSupersededSpellingWritingTests {
    /// A real declaration rather than a literal: it has no writer left, but its published history is
    /// exactly what a resource in a research database carries and what the rewrite has to handle.
    private static let identifier = RetiredFHIRCanonicalURLs.sourceDevice
    private static let canonical = identifier.canonical
    // swiftlint:disable:next force_unwrapping
    private static let legacy = identifier.superseded.first!

    /// The metadata identifier is stood up here rather than imported: `GroveHealthKitFHIR` declares the
    /// canonical and is out of this target's reach. What is under test keys on the retired spelling.
    private static let metadata = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/grove-platform-metadata",
        superseding: SupersededFHIRURLs.metadata
    )

    private func ext(_ url: String, value: String? = nil, children: [Extension] = []) -> Extension {
        var element = Extension(url: FHIRPrimitive(FHIRURI(stringLiteral: url)))
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

    /// The source extensions build nested trees; a shallow copy would produce a legacy-named parent
    /// whose children still carried the canonical spelling — unreadable by the old pipeline.
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

    /// A resource written before the rename carries the superseded spelling and nothing else. The
    /// pass must leave it alone: removing it would destroy the resource's only copy.
    @Test
    func aLegacyOnlyExtensionIsNeverDeleted() throws {
        var subject = observation([ext(Self.legacy, value: "the only copy")])

        subject.writeSupersededSpellings(of: [Self.identifier], policy: .canonicalAndSuperseded)

        let survivor = try #require(subject.extension?.first { $0.urlString == Self.legacy })
        #expect(survivor.value?.stringValue?.value?.string == "the only copy")
        #expect(urls(subject) == [Self.legacy])
    }

    @Test
    func theShippedDefaultIsCanonicalOnly() {
        #expect(FHIRWritePolicy.default == .canonicalOnly)
    }

    /// The point of routing every writer through `append` is that a dual-write reaches extensions no
    /// call site named. If this breaks, opting in silently stops covering whatever was added last.
    @Test
    func appendingDualWritesWithoutTheCallerNamingTheIdentifier() throws {
        let previous = FHIRWritePolicy.default
        defer { FHIRWritePolicy.default = previous }
        FHIRWritePolicy.default = .canonicalAndSuperseded

        var subject = observation([])
        subject.append(extension: ext(Self.canonical, value: "payload"))

        #expect(Set(urls(subject)) == [Self.canonical, Self.legacy])
        let copy = try #require(subject.extension?.first { $0.urlString == Self.legacy })
        #expect(copy.value?.stringValue?.value?.string == "payload")
    }

    @Test
    func appendingUnderTheDefaultPolicyAddsNoCopies() {
        var subject = observation([])
        subject.append(extension: ext(Self.canonical, value: "payload"))
        #expect(urls(subject) == [Self.canonical])
    }

    /// The pre-rename metadata envelope nested the platform key in the url and carried entries the
    /// current writer routes to `effective[x]` and the recording method, so no rewrite of today's
    /// payload rebuilds it. Writing one anyway would file an unseen shape under a trusted name.
    @Test
    func aSpellingWhosePayloadChangedShapeIsNotWritten() throws {
        let retired = try #require(SupersededFHIRURLs.metadata.first)
        var subject = observation([
            ext(Self.metadata.canonical, children: [ext("key"), ext("value", value: "17")])
        ])

        subject.writeSupersededSpellings(of: [Self.metadata], policy: .canonicalAndSuperseded)

        #expect(urls(subject) == [Self.metadata.canonical])
        #expect(!urls(subject).contains(retired))
    }

    /// Skipping the copy must not become deleting the copy a pre-rename resource already carries.
    @Test
    func anExistingCopyOfAShapeChangedSpellingSurvives() throws {
        let retired = try #require(SupersededFHIRURLs.metadata.first)
        var subject = observation([
            ext(Self.metadata.canonical, value: "current"),
            ext(retired, value: "written before the rename")
        ])

        subject.writeSupersededSpellings(of: [Self.metadata], policy: .canonicalAndSuperseded)

        let survivor = try #require(subject.extension?.first { $0.urlString == retired })
        #expect(survivor.value?.stringValue?.value?.string == "written before the rename")
        #expect(urls(subject).count == 2)
    }

    /// A declared identifier has to be reachable from the registry, otherwise the `append` hook
    /// cannot mirror it and a dual-write silently skips that extension. Parameterised over the real
    /// declarations, so dropping one fails here rather than in a consumer's pipeline.
    @Test("declared identifiers reach the registry", arguments: RetiredFHIRCanonicalURLs.all)
    func aDeclaredIdentifierReachesTheRegistry(identifier: FHIRCanonicalURL) throws {
        let registered = try #require(
            FHIRSupersessionRegistry.identifier(forCanonical: identifier.canonical),
            "\(identifier.canonical) retires a spelling but never reached the registry"
        )
        #expect(registered.superseded == identifier.superseded)
    }

    @Test
    func theRegistryOnlyHoldsIdentifiersThatRetiredSomething() {
        #expect(!FHIRSupersessionRegistry.all.isEmpty)
        for identifier in FHIRSupersessionRegistry.all {
            #expect(!identifier.superseded.isEmpty, "\(identifier.canonical) registered without a retired spelling")
        }
    }
}
