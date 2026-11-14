//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveProviderFHIR
import ModelsR4
import Testing


@Suite
struct ProviderSourceApplicationTests {
    private static func result(_ application: SourceApplicationDevice) throws -> ProviderConversionResult {
        let original = try OuraFHIRTests.context()
        let context = ProviderConversionContext(
            producer: original.producer,
            scope: original.scope,
            instant: original.instant,
            sourceTimeZone: original.sourceTimeZone,
            sourceApplication: application
        )
        return try OuraFHIR.convert(.vo2Max(id: "source-writer", timestamp: WithingsFHIRTests.date, value: 42), context: context)
    }

    @Test("Upstream writer identity remains distinct from the converter without invented release or host facts")
    func sourceWriter() throws {
        let identity = try BusinessIdentifier(system: "https://example.org/applications", value: "upstream-app")
        let source = try SourceApplicationDevice(identifiers: [identity])
        let result = try Self.result(source)
        let record = try #require(result.record)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        let provenance = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Provenance }.first)
        let author = try #require(provenance.entity?.first?.agent?.first { $0.type?.coding?.first?.code?.value?.string == "author" })
        let writerURL = try #require(author.who.reference?.value?.string)
        let writerEntry = try #require(bundle.entry?.first { $0.fullUrl?.value?.url.absoluteString == writerURL })
        let writer = try #require(writerEntry.resource?.get() as? Device)
        #expect(writer.identifier?.contains(identity.fhirIdentifier) == true)
        #expect(writer.meta?.profile == [Profile.groveApplicationDevice])
        #expect(writer.parent == nil)
        #expect(writer.version == nil)
        #expect(writer.status == nil)
        #expect(writer.deviceName?.first?.name.value == nil)
        #expect(writer.deviceName?.first?.name.extension?.first?.url == Canonicals.dataAbsentReason)
        #expect(provenance.agent.first?.who.reference != author.who.reference)
        #expect(try Self.result(source).record?.json == record.json)
        try ProviderFixtures.write([result], provider: "source-applications")
    }

    @Test("Source application identifier ordering preserves exact Unicode bytes")
    func exactIdentifiers() throws {
        let composed = try BusinessIdentifier(system: "https://example.org/apps", value: "caf\u{00E9}")
        let decomposed = try BusinessIdentifier(system: "https://example.org/apps", value: "cafe\u{0301}")
        let source = try SourceApplicationDevice(identifiers: [composed, decomposed])
        #expect(source.identifiers.count == 2)
        #expect(source.identifiers[0].value.utf8.elementsEqual(decomposed.value.utf8))
        #expect(source.identifiers[1].value.utf8.elementsEqual(composed.value.utf8))
    }

    @Test("Source identifier order does not change the writer snapshot or retry bytes")
    func identifierOrder() throws {
        let first = try BusinessIdentifier(system: "https://example.org/applications", value: "upstream-app")
        let second = try BusinessIdentifier(system: "https://example.org/clients", value: "public-client")
        let forward = try SourceApplicationDevice(identifiers: [first, second], name: "Upstream App", version: "2.1", build: "18")
        let reverse = try SourceApplicationDevice(identifiers: [second, first], name: "Upstream App", version: "2.1", build: "18")
        #expect(try Self.result(forward).record?.json == Self.result(reverse).record?.json)
        #expect(throws: SourceApplicationDevice.ValidationError.duplicateIdentifier) {
            try SourceApplicationDevice(identifiers: [first, first])
        }
        #expect(throws: SourceApplicationDevice.ValidationError.missingIdentifier) {
            try SourceApplicationDevice(identifiers: [])
        }
    }
}
