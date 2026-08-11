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


/// Minimal stand-in for any resource that carries extensions.
private struct ExtensionCarrier: FHIRTypeWithExtensions {
    // Optionality is the protocol's, matching FHIRModels' own representation.
    var `extension`: [Extension]? // swiftlint:disable:this discouraged_optional_collection

    init(urls: [String]) {
        self.extension = urls.map { url in
            Extension(
                url: URL(string: url)!.asFHIRURIPrimitive(), // swiftlint:disable:this force_unwrapping
                value: .string(url.asFHIRStringPrimitive())
            )
        }
    }
}


/// Canonical URLs identify extensions inside resources this project does not own — questionnaires
/// authored elsewhere, observations already in a research database — so a superseded spelling has to
/// keep resolving indefinitely.
@Suite
struct FHIRCanonicalURLTests {
    private static let identifier = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/validationText",
        superseding: SupersededFHIRURLs.validationText
    )

    private func item(withExtensionsAt urls: [String]) -> ExtensionCarrier {
        ExtensionCarrier(urls: urls)
    }

    private func value(of extensions: [Extension]) -> [String] {
        extensions.compactMap { $0.value?.stringValue?.value?.string }
    }

    @Test
    func findsTheCanonicalSpelling() {
        let found = item(withExtensionsAt: [Self.identifier.canonical]).extensions(for: Self.identifier)
        #expect(value(of: found) == [Self.identifier.canonical])
    }

    @Test("every superseded spelling still resolves", arguments: SupersededFHIRURLs.validationText)
    func findsEachSupersededSpelling(_ spelling: String) {
        let found = item(withExtensionsAt: [spelling]).extensions(for: Self.identifier)
        #expect(value(of: found) == [spelling])
    }

    /// A resource carrying both was written by a newer version; the superseded copy is a compatibility
    /// duplicate and must not be preferred, nor merged in alongside.
    @Test
    func theCanonicalSpellingWinsWhenBothArePresent() throws {
        let legacy = try #require(SupersededFHIRURLs.validationText.first)
        let found = item(withExtensionsAt: [legacy, Self.identifier.canonical]).extensions(for: Self.identifier)

        #expect(value(of: found) == [Self.identifier.canonical])
    }

    @Test
    func findsNothingWhenNoSpellingIsPresent() {
        let found = item(withExtensionsAt: ["http://example.org/other"]).extensions(for: Self.identifier)
        #expect(found.isEmpty)
    }

    /// The two pre-Grove spellings of the validation message predate each other, so both have to be
    /// carried — dropping the older one would break questionnaires written before it was superseded.
    @Test
    func carriesEverySpellingEverPublished() {
        #expect(Self.identifier.allSpellings.count == SupersededFHIRURLs.validationText.count + 1)
        #expect(Self.identifier.allSpellings.first == Self.identifier.canonical)
        #expect(Set(SupersededFHIRURLs.validationText).isSubset(of: Set(Self.identifier.allSpellings)))
    }

    /// Only the authority may carry an organisation. A product or module name in the path would have
    /// to change at the next rename, and a published canonical URL never can.
    @Test("no published path names a product", arguments: [
        FHIRCanonicalURL("https://grovealliance.org/fhir/core/StructureDefinition/validationText"),
        FHIRCanonicalURL("https://grovealliance.org/fhir/core/StructureDefinition/iosKeyboardType"),
        FHIRCanonicalURL("https://grovealliance.org/fhir/core/StructureDefinition/iosTextContentType"),
        FHIRCanonicalURL("https://grovealliance.org/fhir/core/StructureDefinition/iosAutocapitalizationType")
    ])
    func pathsNameConceptsNotProducts(_ identifier: FHIRCanonicalURL) throws {
        let path = try #require(URL(string: identifier.canonical)?.path)
        for token in ["spezi", "grove", "stanford", "bdh", "biodesign", "cardinalkit"] {
            #expect(!path.lowercased().contains(token), "'\(token)' must not appear in \(path)")
        }
        #expect(identifier.canonical.hasPrefix("https://"))
    }
}
