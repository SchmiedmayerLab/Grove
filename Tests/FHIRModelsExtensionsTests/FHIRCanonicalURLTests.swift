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


/// Canonical URLs are exact identifiers. Grove v0.2 does not alias retired spellings.
@Suite
struct FHIRCanonicalURLTests {
    private static let identifier = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/validationText"
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

    @Test
    func doesNotResolveANearMatch() {
        let nearMatch = Self.identifier.canonical + "-old"
        let found = item(withExtensionsAt: [nearMatch]).extensions(for: Self.identifier)

        #expect(found.isEmpty)
    }

    @Test
    func findsNothingWhenNoSpellingIsPresent() {
        let found = item(withExtensionsAt: ["http://example.org/other"]).extensions(for: Self.identifier)
        #expect(found.isEmpty)
    }

    @Test
    func preservesTheExactCanonical() {
        #expect(Self.identifier.description == Self.identifier.canonical)
    }
}
