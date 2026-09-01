//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Mutation cases remain next to the rule matrix they assert, and helpers follow the scenario tests.
// swiftlint:disable function_body_length type_contents_order file_length type_body_length nesting

import Foundation
@testable import GroveFHIRContract
import ModelsR4
import Testing


private let exchangeGraphCorpusDirectory: URL = {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        repositoryRoot.appendingPathComponent(
            ".fhir/grove-fhir/Conformance/corpora/mobile-exchange",
            isDirectory: true
        ),
        repositoryRoot.deletingLastPathComponent().appendingPathComponent(
            "grove-fhir/Conformance/corpora/mobile-exchange",
            isDirectory: true
        )
    ]
    return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? candidates[0]
}()

private let exchangeGraphCorpusIsAvailable = FileManager.default.fileExists(
    atPath: exchangeGraphCorpusDirectory.appendingPathComponent("corpus.json").path
)


@Suite(.enabled(
    if: exchangeGraphCorpusIsAvailable,
    "Requires the grove-fhir checkout used by FHIR Output Conformance"
))
struct ExchangeGraphCorpusTests {
    private struct CorpusManifest: Decodable {
        struct Base: Decodable {
            let id: String
            let path: String
        }

        struct Case: Decodable {
            struct ExpectedRule: Decodable {
                let code: String
                let reason: String
                let location: String
                let severity: ExchangeGraphDiagnostic.Severity

                var diagnostic: ExchangeGraphDiagnostic {
                    ExchangeGraphDiagnostic(
                        code: code,
                        reason: reason,
                        location: location,
                        severity: severity
                    )
                }
            }

            let id: String
            let base: String
            let expectedRule: ExpectedRule
        }

        let bases: [Base]
        let cases: [Case]
    }

    private struct CorpusPatchError: Error {}

    @Test("The shared active and retraction fixtures are accepted as authoritative graphs")
    func acceptsSharedFixtures() throws {
        _ = try graph(named: "exchange-bundle.json", kind: .active)
        _ = try graph(named: "retraction-bundle.json", kind: .retraction)
    }

    @Test("Provider-owned semantics require their exact provider envelope")
    func providerOwnedSemanticEnvelope() throws {
        let semantic = Profile.ouraReadinessScore
        let correct = Profile.ouraObservation
        let wrong = Profile.withingsObservation
        let generic = Profile.providersObservation

        func observation(_ profiles: [FHIRPrimitive<Canonical>]) -> Observation {
            Observation(
                code: CodeableConcept(),
                meta: Meta(profile: profiles),
                status: FHIRPrimitive(.final)
            )
        }

        try ExchangeGraph.validateObservationProfileClaim(observation([semantic, correct]))
        #expect(throws: ExchangeGraphError.ruleViolation(.semanticProfile)) {
            try ExchangeGraph.validateObservationProfileClaim(observation([semantic]))
        }
        #expect(throws: ExchangeGraphError.ruleViolation(.semanticProfile)) {
            try ExchangeGraph.validateObservationProfileClaim(observation([semantic, wrong]))
        }
        #expect(throws: ExchangeGraphError.ruleViolation(.semanticProfile)) {
            try ExchangeGraph.validateObservationProfileClaim(observation([semantic, generic]))
        }
    }

    @Test("Every shared mutation names a closed Swift producer rule")
    func consumesSharedCorpusManifest() throws {
        let manifest = try JSONDecoder().decode(
            CorpusManifest.self,
            from: Data(contentsOf: corpusDirectory.appendingPathComponent("corpus.json"))
        )
        #expect(!manifest.cases.isEmpty)
        for testCase in manifest.cases {
            #expect(
                ExchangeGraphRule(rawValue: testCase.expectedRule.code) != nil,
                "Missing Swift rule for shared mutation \(testCase.id)"
            )
        }
    }

    @Test("Every Swift producer rule is registered with the guide's exact code and reason")
    func rulesMatchThePinnedRegistry() throws {
        struct Registry: Decodable {
            struct Diagnostic: Decodable {
                let code: String
                let reason: String
            }

            let producerDiagnostics: [Diagnostic]
        }

        let registry = try JSONDecoder().decode(
            Registry.self,
            from: Data(contentsOf: protocolCatalogURL)
        )
        let reasonsByCode = Dictionary(
            uniqueKeysWithValues: registry.producerDiagnostics.map { ($0.code, $0.reason) }
        )
        for rule in ExchangeGraphRule.allCases {
            let registered = reasonsByCode[rule.rawValue]
            #expect(registered != nil, "Unregistered producer rule \(rule.rawValue)")
            #expect(
                registered == rule.diagnostic.reason,
                "Reason drift for \(rule.rawValue): \(rule.diagnostic.reason)"
            )
        }
    }

    @Test("Every shared mutation reports the exact structured Grove diagnostic")
    func reportsExactSharedCorpusDiagnostics() throws {
        let corpusURL = corpusDirectory.appendingPathComponent("corpus.json")
        let data = try Data(contentsOf: corpusURL)
        let manifest = try JSONDecoder().decode(CorpusManifest.self, from: data)
        let rawManifest = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let rawCases = try #require(rawManifest["cases"] as? [[String: Any]])
        let rawCasesByID = Dictionary(uniqueKeysWithValues: try rawCases.map { rawCase in
            (try #require(rawCase["id"] as? String), rawCase)
        })
        let basePaths = Dictionary(uniqueKeysWithValues: manifest.bases.map { ($0.id, $0.path) })

        for testCase in manifest.cases {
            let rawCase = try #require(rawCasesByID[testCase.id])
            let operations = try #require(rawCase["patch"] as? [[String: Any]])
            let basePath = try #require(basePaths[testCase.base])
            let baseObject = try JSONSerialization.jsonObject(
                with: Data(contentsOf: corpusDirectory.appendingPathComponent(basePath))
            )
            let mutated = try applying(operations, to: baseObject)
            let mutatedData = try JSONSerialization.data(withJSONObject: mutated)
            let kind: ExchangeGraphKind = testCase.base == "mobile-retraction" ? .retraction : .active

            do {
                _ = try ExchangeGraph(kind: kind, jsonData: mutatedData)
                Issue.record("Corpus mutation \(testCase.id) was accepted")
            } catch {
                #expect(
                    error.diagnostic == testCase.expectedRule.diagnostic,
                    "Corpus mutation \(testCase.id) reported \(String(describing: error.diagnostic))"
                )
            }
        }
    }

    @Test("The shared structural mutations report stable Grove producer rules")
    func reportsStableRules() throws {
        var missingKey = try bundle(named: "exchange-bundle.json")
        var entries = try #require(missingKey.entry)
        entries[0].extension = nil
        missingKey.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.entryNodeKey)) {
            try validate(missingKey, kind: .active)
        }

        var wrongFullURL = try bundle(named: "exchange-bundle.json")
        entries = try #require(wrongFullURL.entry)
        entries[1].fullUrl = "urn:uuid:00000000-0000-5000-8000-000000000000"
        wrongFullURL.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.deterministicFullURL)) {
            try validate(wrongFullURL, kind: .active)
        }

        var wrongSubjectTarget = try bundle(named: "exchange-bundle.json")
        entries = try #require(wrongSubjectTarget.entry)
        guard case .observation(var wrongSubjectObservation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        let subject = try #require(wrongSubjectObservation.subject)
        wrongSubjectObservation.subject = Reference(
            display: subject.display,
            extension: subject.extension,
            id: subject.id,
            identifier: subject.identifier,
            reference: entries[1].fullUrl?.value?.url.absoluteString.asFHIRStringPrimitive(),
            type: subject.type
        )
        entries[2].resource = ResourceProxy(with: wrongSubjectObservation)
        wrongSubjectTarget.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.referenceTargetType)) {
            try validate(wrongSubjectTarget, kind: .active)
        }

        var falseDeclaredType = try bundle(named: "exchange-bundle.json")
        entries = try #require(falseDeclaredType.entry)
        guard case .observation(var falseTypeObservation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        let falseTypeSubject = try #require(falseTypeObservation.subject)
        falseTypeObservation.subject = Reference(
            display: falseTypeSubject.display,
            extension: falseTypeSubject.extension,
            id: falseTypeSubject.id,
            identifier: falseTypeSubject.identifier,
            reference: falseTypeSubject.reference,
            type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.device.rawValue))
        )
        entries[2].resource = ResourceProxy(with: falseTypeObservation)
        falseDeclaredType.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.referenceDeclaredType)) {
            try validate(falseDeclaredType, kind: .active)
        }

        var mixedSubject = try bundle(named: "exchange-bundle.json")
        entries = try #require(mixedSubject.entry)
        guard case .observation(var mixedSubjectObservation)? = entries[2].resource,
              let mixedLiteral = mixedSubjectObservation.subject?.reference else {
            Issue.record("Fixture output has no literal Observation.subject")
            return
        }
        mixedSubjectObservation.subject = Reference(
            identifier: Identifier(
                system: "https://study.example.org/fhir/identifiers/participant",
                value: "participant-1"
            ),
            reference: mixedLiteral,
            type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.patient.rawValue))
        )
        entries[2].resource = ResourceProxy(with: mixedSubjectObservation)
        mixedSubject.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.referenceShape)) {
            try validate(mixedSubject, kind: .active)
        }

        var untypedLogicalSubject = try bundle(named: "exchange-bundle.json")
        entries = try #require(untypedLogicalSubject.entry)
        guard case .observation(var untypedSubjectObservation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        untypedSubjectObservation.subject = Reference(identifier: Identifier(
            system: "https://study.example.org/fhir/identifiers/participant",
            value: "participant-1"
        ))
        entries[2].resource = ResourceProxy(with: untypedSubjectObservation)
        untypedLogicalSubject.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.logicalPatientReference)) {
            try validate(untypedLogicalSubject, kind: .active)
        }

        var unresolvedLiteral = try bundle(named: "exchange-bundle.json")
        entries = try #require(unresolvedLiteral.entry)
        guard case .observation(var unresolvedObservation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        unresolvedObservation.subject = Reference(reference: "Patient/not-in-this-bundle")
        entries[2].resource = ResourceProxy(with: unresolvedObservation)
        unresolvedLiteral.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.resolvedReference)) {
            try validate(unresolvedLiteral, kind: .active)
        }

        var tamperedNode = try bundle(named: "exchange-bundle.json")
        entries = try #require(tamperedNode.entry)
        // Tampering the Provenance's own key keeps the digest the only defect: giving another
        // entry the conversion-provenance role would misnumber that role's ordinal instead.
        let provenanceIndex = try #require(entries.firstIndex {
            if case .provenance = $0.resource {
                return true
            }
            return false
        })
        var nodeExtensions = try #require(entries[provenanceIndex].extension)
        guard case .identifier(var nodeIdentifier)? = nodeExtensions[0].value else {
            Issue.record("Fixture entry key is not an Identifier")
            return
        }
        nodeIdentifier = Identifier(
            assigner: nodeIdentifier.assigner,
            extension: nodeIdentifier.extension,
            id: nodeIdentifier.id,
            period: nodeIdentifier.period,
            system: nodeIdentifier.system,
            type: nodeIdentifier.type,
            use: nodeIdentifier.use,
            value: "n0:conversion-provenance:0:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
        nodeExtensions[0].value = .identifier(nodeIdentifier)
        entries[provenanceIndex].extension = nodeExtensions
        entries[provenanceIndex].fullUrl = FHIRPrimitive(FHIRURI(
            stringLiteral: try ExchangeIdentity.fullURL(for: BusinessIdentifier(nodeIdentifier))
        ))
        tamperedNode.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.entryNodeDigest)) {
            try validate(tamperedNode, kind: .active)
        }

        var missingOutputIdentity = try bundle(named: "exchange-bundle.json")
        entries = try #require(missingOutputIdentity.entry)
        guard case .observation(var observation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        observation.identifier = try observation.identifier?.filter {
            try BusinessIdentifier($0).role != .sourceOutput
        }
        entries[2].resource = ResourceProxy(with: observation)
        missingOutputIdentity.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.sourceOutputRequired)) {
            try validate(missingOutputIdentity, kind: .active)
        }

        var duplicateSourceIdentity = try bundle(named: "exchange-bundle.json")
        entries = try #require(duplicateSourceIdentity.entry)
        guard case .observation(var duplicateObservation)? = entries[2].resource,
              let sourceRecord = try duplicateObservation.identifier?.first(where: {
                  try BusinessIdentifier($0).role == .sourceRecord
              }) else {
            Issue.record("Fixture output has no source-record Identifier")
            return
        }
        duplicateObservation.identifier?.append(sourceRecord)
        entries[2].resource = ResourceProxy(with: duplicateObservation)
        duplicateSourceIdentity.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.sourceOutputRequired)) {
            try validate(duplicateSourceIdentity, kind: .active)
        }

        var missingProvenance = try bundle(named: "exchange-bundle.json")
        entries = try #require(missingProvenance.entry)
        entries.removeAll { entry in
            if case .provenance? = entry.resource {
                return true
            }
            return false
        }
        missingProvenance.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.transformProvenance)) {
            try validate(missingProvenance, kind: .active)
        }
    }

    @Test("Retraction fixtures reject commands, clear targets, and copied clinical resources")
    func rejectsInvalidRetractions() throws {
        var literalTarget = try bundle(named: "retraction-bundle.json")
        var entries = try #require(literalTarget.entry)
        guard case .provenance(var provenance)? = entries[0].resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        let originalTarget = provenance.target[0]
        provenance.target[0] = Reference(
            display: originalTarget.display,
            extension: originalTarget.extension,
            id: originalTarget.id,
            identifier: originalTarget.identifier,
            reference: "Observation/prior-output",
            type: originalTarget.type
        )
        entries[0].resource = ResourceProxy(with: provenance)
        literalTarget.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.retractionLogicalTarget)) {
            try validate(literalTarget, kind: .retraction)
        }

        var unknownRole = try bundle(named: "retraction-bundle.json")
        entries = try #require(unknownRole.entry)
        guard case .provenance(var unknownRoleProvenance)? = entries[0].resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        let unknownRoleTarget = unknownRoleProvenance.target[0]
        var roleExtensions = try #require(unknownRoleTarget.extension)
        roleExtensions[0].value = .code("delete-command")
        unknownRoleProvenance.target[0] = Reference(
            display: unknownRoleTarget.display,
            extension: roleExtensions,
            id: unknownRoleTarget.id,
            identifier: unknownRoleTarget.identifier,
            reference: unknownRoleTarget.reference,
            type: unknownRoleTarget.type
        )
        entries[0].resource = ResourceProxy(with: unknownRoleProvenance)
        unknownRole.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.retractionTargetRole)) {
            try validate(unknownRole, kind: .retraction)
        }

        var mismatchedTargetType = try bundle(named: "retraction-bundle.json")
        entries = try #require(mismatchedTargetType.entry)
        guard case .provenance(var mismatchedTypeProvenance)? = entries[0].resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        let mismatchedTarget = mismatchedTypeProvenance.target[0]
        mismatchedTypeProvenance.target[0] = Reference(
            display: mismatchedTarget.display,
            extension: mismatchedTarget.extension,
            id: mismatchedTarget.id,
            identifier: mismatchedTarget.identifier,
            reference: mismatchedTarget.reference,
            type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.device.rawValue))
        )
        entries[0].resource = ResourceProxy(with: mismatchedTypeProvenance)
        mismatchedTargetType.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.retractionRoleTargetType)) {
            try validate(mismatchedTargetType, kind: .retraction)
        }

        var clearTarget = try bundle(named: "retraction-bundle.json")
        entries = try #require(clearTarget.entry)
        guard case .provenance(var clearTargetProvenance)? = entries[0].resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        let clearTargetOriginal = clearTargetProvenance.target[0]
        let originalIdentifier = try #require(clearTargetOriginal.identifier)
        let clearIdentifier = Identifier(
            assigner: originalIdentifier.assigner,
            extension: originalIdentifier.extension,
            id: originalIdentifier.id,
            period: originalIdentifier.period,
            system: originalIdentifier.system,
            type: originalIdentifier.type,
            use: originalIdentifier.use,
            value: "prior-output-001"
        )
        clearTargetProvenance.target[0] = Reference(
            display: clearTargetOriginal.display,
            extension: clearTargetOriginal.extension,
            id: clearTargetOriginal.id,
            identifier: clearIdentifier,
            reference: clearTargetOriginal.reference,
            type: clearTargetOriginal.type
        )
        entries[0].resource = ResourceProxy(with: clearTargetProvenance)
        clearTarget.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.retractionOpaqueTarget)) {
            try validate(clearTarget, kind: .retraction)
        }

        var copiedClinical = try bundle(named: "retraction-bundle.json")
        entries = try #require(copiedClinical.entry)
        entries[0].resource = ResourceProxy(with: Observation(
            code: CodeableConcept(),
            status: FHIRPrimitive(.final)
        ))
        copiedClinical.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.retractionNoClinicalCopy)) {
            try validate(copiedClinical, kind: .retraction)
        }
    }

    @Test("Lifecycle systems have exact coding cardinality while unrelated translations stay open")
    func lifecycleCodingCardinality() throws {
        let isoSystem = "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"
        let groveSystem = "https://grovealliance.org/fhir/mobile/CodeSystem/grove-lifecycle-event"
        let translation = Coding(
            code: "translated".asFHIRStringPrimitive(),
            system: "https://example.org/CodeSystem/local-lifecycle".asFHIRURIPrimitive()
        )

        var activeDuplicate = try bundle(named: "exchange-bundle.json")
        try appendActivityCoding(
            Coding(code: "transform".asFHIRStringPrimitive(), system: isoSystem.asFHIRURIPrimitive()),
            to: &activeDuplicate
        )
        #expect(throws: ExchangeGraphError.ruleViolation(.lifecycleCoding)) {
            try validate(activeDuplicate, kind: .active)
        }

        var activeOpposite = try bundle(named: "exchange-bundle.json")
        try appendActivityCoding(
            Coding(
                code: "source-record-retracted".asFHIRStringPrimitive(),
                system: groveSystem.asFHIRURIPrimitive()
            ),
            to: &activeOpposite
        )
        #expect(throws: ExchangeGraphError.ruleViolation(.lifecycleCoding)) {
            try validate(activeOpposite, kind: .active)
        }

        var activeTranslation = try bundle(named: "exchange-bundle.json")
        try appendActivityCoding(translation, to: &activeTranslation)
        _ = try validate(activeTranslation, kind: .active)

        var retractionDuplicate = try bundle(named: "retraction-bundle.json")
        try appendActivityCoding(
            Coding(
                code: "source-record-retracted".asFHIRStringPrimitive(),
                system: groveSystem.asFHIRURIPrimitive()
            ),
            to: &retractionDuplicate
        )
        #expect(throws: ExchangeGraphError.ruleViolation(.lifecycleCoding)) {
            try validate(retractionDuplicate, kind: .retraction)
        }

        var retractionOpposite = try bundle(named: "retraction-bundle.json")
        try appendActivityCoding(
            Coding(code: "transform".asFHIRStringPrimitive(), system: isoSystem.asFHIRURIPrimitive()),
            to: &retractionOpposite
        )
        #expect(throws: ExchangeGraphError.ruleViolation(.lifecycleCoding)) {
            try validate(retractionOpposite, kind: .retraction)
        }

        var retractionTranslation = try bundle(named: "retraction-bundle.json")
        try appendActivityCoding(translation, to: &retractionTranslation)
        _ = try validate(retractionTranslation, kind: .retraction)
    }

    @Test("Contained resources and fragment references are prohibited")
    func rejectsContainedResourcesAndReferences() throws {
        var unresolved = try bundle(named: "exchange-bundle.json")
        var entries = try #require(unresolved.entry)
        guard case .observation(var observation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        observation.subject = Reference(reference: "#missing-patient")
        entries[2].resource = ResourceProxy(with: observation)
        unresolved.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.containedResourceProhibited)) {
            try validate(unresolved, kind: .active)
        }

        var duplicate = try rawBundle(named: "exchange-bundle.json")
        var rawEntries = try #require(duplicate["entry"] as? [[String: Any]])
        var outputEntry = rawEntries[2]
        var outputResource = try #require(outputEntry["resource"] as? [String: Any])
        outputResource["contained"] = [
            ["resourceType": "Patient", "id": "duplicate-patient"],
            ["resourceType": "Patient", "id": "duplicate-patient"]
        ]
        outputEntry["resource"] = outputResource
        rawEntries[2] = outputEntry
        duplicate["entry"] = rawEntries
        let duplicateBundle = try JSONDecoder().decode(
            ModelsR4.Bundle.self,
            from: JSONSerialization.data(withJSONObject: duplicate)
        )
        #expect(throws: ExchangeGraphError.ruleViolation(.containedResourceProhibited)) {
            try validate(duplicateBundle, kind: .active)
        }
    }

    @Test("Adapter-only outputs cannot shed their exact adapter profile")
    func adapterOnlyOutputProfile() throws {
        var bundle = try bundle(named: "exchange-bundle.json")
        var entries = try #require(bundle.entry)
        guard case .observation(let observation)? = entries[2].resource else {
            Issue.record("Fixture output is not an Observation")
            return
        }
        entries[2].resource = ResourceProxy(with: Specimen(
            identifier: observation.identifier,
            meta: observation.meta,
            subject: observation.subject
        ))
        bundle.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.adapterOnlyProfile)) {
            try validate(bundle, kind: .active)
        }
    }

    @Test("Graph validation admits integer zero and rejects fractional event totals")
    func validatesCatalogQuantityDomains() throws {
        var raw = try rawBundle(named: "exchange-bundle.json")
        var entries = try #require(raw["entry"] as? [[String: Any]])
        var output = try #require(entries[2]["resource"] as? [String: Any])
        var meta = try #require(output["meta"] as? [String: Any])
        var profiles = try #require(meta["profile"] as? [String])
        profiles[0] = try #require(Profile.groveMobileStepCount.value?.url.absoluteString)
        meta["profile"] = profiles
        output["meta"] = meta
        var quantity = try #require(output["valueQuantity"] as? [String: Any])
        quantity["code"] = "{steps}"
        quantity["unit"] = "steps"
        quantity["value"] = 0
        output["valueQuantity"] = quantity
        entries[2]["resource"] = output
        raw["entry"] = entries

        _ = try ExchangeGraph(
            kind: .active,
            jsonData: JSONSerialization.data(withJSONObject: raw)
        )

        quantity["value"] = 1.5
        output["valueQuantity"] = quantity
        entries[2]["resource"] = output
        raw["entry"] = entries
        let fractionalData = try JSONSerialization.data(withJSONObject: raw)
        do {
            _ = try ExchangeGraph(
                kind: .active,
                jsonData: fractionalData
            )
            Issue.record("Fractional step count was accepted")
        } catch {
            #expect(error.diagnostic.code == ExchangeGraphRule.quantityValueDomain.rawValue)
        }
    }

    @Test("Decimal domain checks do not round a just-out-of-range percentage through binary64")
    func validatesCatalogQuantityDomainsAsDecimals() throws {
        var bundle = try bundle(named: "exchange-bundle.json")
        var entries = try #require(bundle.entry)
        guard case .observation(var observation)? = entries[2].resource else {
            Issue.record("Fixture output is not Observation")
            return
        }
        var meta = try #require(observation.meta)
        var profiles = try #require(meta.profile)
        profiles[0] = Profile.groveMobileOxygenSaturation
        meta.profile = profiles
        observation.meta = meta
        guard case .quantity(var quantity)? = observation.value else {
            Issue.record("Fixture value is not Quantity")
            return
        }
        let decimal = try #require(Decimal(
            string: "100.0000000000000000000000001",
            locale: Locale(identifier: "en_US_POSIX")
        ))
        quantity.code = "%".asFHIRStringPrimitive()
        quantity.unit = "%".asFHIRStringPrimitive()
        quantity.value = FHIRPrimitive(FHIRDecimal(decimal))
        observation.value = .quantity(quantity)
        entries[2].resource = ResourceProxy(with: observation)
        bundle.entry = entries

        do {
            _ = try validate(bundle, kind: .active)
            Issue.record("Out-of-range high-precision percentage was accepted")
        } catch let error as ExchangeGraphError {
            #expect(error.diagnostic.code == ExchangeGraphRule.quantityValueDomain.rawValue)
        } catch {
            Issue.record("Unexpected validation error: \(error)")
        }
    }

    @Test("A failure the registry does not name reports the unclassified diagnostic")
    func unregisteredFailuresReportUnclassified() throws {
        var undated = try bundle(named: "exchange-bundle.json")
        undated.timestamp = nil
        do {
            _ = try validate(undated, kind: .active)
            Issue.record("A bundle without a timestamp was accepted")
        } catch let error as ExchangeGraphError {
            #expect(error.diagnostic == ExchangeGraphRule.unclassified.diagnostic)
        }
        #expect(ExchangeGraph.rule(for: .missingResource) == .unclassified)
    }

    @Test("The retraction builder carries its source-record entity")
    func retractionBuilderCarriesSourceEntity() throws {
        let fixture = try bundle(named: "retraction-bundle.json")
        guard case .provenance(let fixtureProvenance)? = fixture.entry?.first?.resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        let sourceRecord = try BusinessIdentifier(
            #require(fixtureProvenance.entity?.first?.what.identifier)
        )
        let fixtureTarget = try #require(fixtureProvenance.target.first)
        let targetType = try #require(fixtureTarget.type?.value?.url.absoluteString)
        let resourceType = try #require(ResourceType(rawValue: targetType))
        let target = try RetractionTarget(
            identifier: BusinessIdentifier(#require(fixtureTarget.identifier)),
            resourceType: resourceType,
            role: .primaryOutput
        )
        let event = try ExchangeEventIdentifier(BusinessIdentifier(#require(fixture.identifier)))
        let graph = try RetractionEventBuilder.build(
            targets: [target],
            context: RetractionEventContext(
                eventIdentifier: event,
                entryNodeIdentifierSystem: "https://study.example.org/fhir/NamingSystem/retraction-node-v0",
                producer: fixtureProvenance.agent[0].who,
                sourceRecord: sourceRecord,
                sourceRetractionTime: Date(timeIntervalSince1970: 1_787_299_200),
                recordedAt: Date(timeIntervalSince1970: 1_787_299_201)
            )
        )
        guard case .provenance(let provenance)? = graph.bundle.entry?.first?.resource else {
            Issue.record("Builder did not emit Provenance")
            return
        }
        #expect(try BusinessIdentifier(#require(provenance.entity?.first?.what.identifier)) == sourceRecord)
    }

    @Test("An authorized native record identifier rides beside the opaque retraction target")
    func retractionTargetCarriesTheNativeRecordIdentifier() throws {
        let fixture = try bundle(named: "retraction-bundle.json")
        guard case .provenance(let fixtureProvenance)? = fixture.entry?.first?.resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        let sourceRecord = try BusinessIdentifier(
            #require(fixtureProvenance.entity?.first?.what.identifier)
        )
        let fixtureTarget = try #require(fixtureProvenance.target.first)
        let targetIdentifier = try BusinessIdentifier(#require(fixtureTarget.identifier))
        let targetType = try #require(fixtureTarget.type?.value?.url.absoluteString)
        let resourceType = try #require(ResourceType(rawValue: targetType))
        let policy = GovernedSourceIdentifierDisclosurePolicy.authorized(
            system: "https://study.example.org/fhir/NamingSystem/source-store"
        )
        let nativeRecordID = "8ad4f0f6-2f11-4f5a-9d0f-51f3a1c0b2e7"
        let target = try RetractionTarget(
            identifier: targetIdentifier,
            resourceType: resourceType,
            role: .primaryOutput,
            nativeRecordIdentifier: policy.identifier(for: nativeRecordID)
        )
        let graph = try RetractionEventBuilder.build(
            targets: [target],
            context: RetractionEventContext(
                eventIdentifier: ExchangeEventIdentifier(BusinessIdentifier(#require(fixture.identifier))),
                entryNodeIdentifierSystem: "https://study.example.org/fhir/NamingSystem/retraction-node-v0",
                producer: fixtureProvenance.agent[0].who,
                sourceRecord: sourceRecord,
                sourceRetractionTime: Date(timeIntervalSince1970: 1_787_299_200),
                recordedAt: Date(timeIntervalSince1970: 1_787_299_201)
            )
        )
        guard case .provenance(let provenance)? = graph.bundle.entry?.first?.resource else {
            Issue.record("Builder did not emit Provenance")
            return
        }
        let disclosed = try #require(provenance.target.first?.extension?.first {
            $0.url == Canonicals.retractionTargetNativeIdentifier
        })
        guard case .identifier(let identifier)? = disclosed.value else {
            Issue.record("The native record identifier is not an Identifier")
            return
        }
        #expect(identifier.value?.value?.string == nativeRecordID)
        #expect(identifier.system?.value?.url.absoluteString == "https://study.example.org/fhir/NamingSystem/source-store")

        // The opaque Grove identity is never restated as the clear native one.
        #expect(throws: RetractionTargetError.invalidNativeRecordIdentifier) {
            try RetractionTarget(
                identifier: targetIdentifier,
                resourceType: resourceType,
                role: .primaryOutput,
                nativeRecordIdentifier: sourceRecord.fhirIdentifier
            )
        }

        // A role coding refuses the target even when its code is not one Grove recognises.
        let unrecognisedRole = Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: "https://study.example.org/fhir/NamingSystem/source-store")),
            type: CodeableConcept(coding: [
    Coding(
                    code: "not-a-grove-role".asFHIRStringPrimitive(),
                    system: Canonicals.identifierRoleCodeSystem
                )
            ]),
            value: nativeRecordID.asFHIRStringPrimitive()
        )
        #expect(throws: RetractionTargetError.invalidNativeRecordIdentifier) {
            try RetractionTarget(
                identifier: targetIdentifier,
                resourceType: resourceType,
                role: .primaryOutput,
                nativeRecordIdentifier: unrecognisedRole
            )
        }
    }

    private func graph(named name: String, kind: ExchangeGraphKind) throws -> ExchangeGraph {
        try validate(bundle(named: name), kind: kind)
    }

    private func validate(_ bundle: ModelsR4.Bundle, kind: ExchangeGraphKind) throws -> ExchangeGraph {
        let identifier = try BusinessIdentifier(#require(bundle.identifier))
        return try ExchangeGraph(
            kind: kind,
            eventIdentifier: ExchangeEventIdentifier(identifier),
            bundle: bundle
        )
    }

    private func bundle(named name: String) throws -> ModelsR4.Bundle {
        try JSONDecoder().decode(
            ModelsR4.Bundle.self,
            from: Data(contentsOf: corpusDirectory.appendingPathComponent(name))
        )
    }

    private func rawBundle(named name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: corpusDirectory.appendingPathComponent(name))
        )
        return try #require(object as? [String: Any])
    }

    private func applying(
        _ operations: [[String: Any]],
        to root: Any
    ) throws -> Any {
        var result = root
        for operation in operations {
            guard let operationName = operation["op"] as? String,
                  let rawPath = operation["path"] as? String,
                  rawPath.first == "/" else {
                throw CorpusPatchError()
            }
            let path = rawPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
                String($0).replacingOccurrences(of: "~1", with: "/")
                    .replacingOccurrences(of: "~0", with: "~")
            }
            result = try applying(
                operation: operationName,
                path: ArraySlice(path),
                replacement: operation["value"],
                to: result
            )
        }
        return result
    }

    private func applying(
        operation: String,
        path: ArraySlice<String>,
        replacement: Any?,
        to value: Any
    ) throws -> Any {
        guard let component = path.first else {
            throw CorpusPatchError()
        }
        let remaining = path.dropFirst()
        if let object = value as? [String: Any] {
            return try applying(
                operation: operation,
                component: component,
                path: remaining,
                replacement: replacement,
                to: object
            )
        }
        if let array = value as? [Any] {
            return try applying(
                operation: operation,
                component: component,
                path: remaining,
                replacement: replacement,
                to: array
            )
        }
        throw CorpusPatchError()
    }

    private func applying(
        operation: String,
        component: String,
        path: ArraySlice<String>,
        replacement: Any?,
        to source: [String: Any]
    ) throws -> Any {
        var object = source
        if path.isEmpty {
            switch operation {
            case "remove":
                guard object.removeValue(forKey: component) != nil else {
                    throw CorpusPatchError()
                }
            case "add", "replace":
                guard let replacement,
                      operation == "add" || object[component] != nil else {
                    throw CorpusPatchError()
                }
                object[component] = replacement
            default:
                throw CorpusPatchError()
            }
            return object
        }
        guard let child = object[component] else {
            throw CorpusPatchError()
        }
        object[component] = try applying(
            operation: operation,
            path: path,
            replacement: replacement,
            to: child
        )
        return object
    }

    private func applying(
        operation: String,
        component: String,
        path: ArraySlice<String>,
        replacement: Any?,
        to source: [Any]
    ) throws -> Any {
        var array = source
        if path.isEmpty {
            return try applyingTerminalArrayOperation(
                operation: operation,
                component: component,
                replacement: replacement,
                to: array
            )
        }
        guard let index = Int(component), index >= 0 else {
            throw CorpusPatchError()
        }
        guard array.indices.contains(index) else {
            throw CorpusPatchError()
        }
        array[index] = try applying(
            operation: operation,
            path: path,
            replacement: replacement,
            to: array[index]
        )
        return array
    }

    private func applyingTerminalArrayOperation(
        operation: String,
        component: String,
        replacement: Any?,
        to source: [Any]
    ) throws -> [Any] {
        var array = source
        if component == "-" {
            guard operation == "add", let replacement else {
                throw CorpusPatchError()
            }
            array.append(replacement)
            return array
        }
        guard let index = Int(component), index >= 0 else {
            throw CorpusPatchError()
        }
        switch operation {
        case "remove":
            guard array.indices.contains(index) else {
                throw CorpusPatchError()
            }
            array.remove(at: index)
        case "replace":
            guard array.indices.contains(index), let replacement else {
                throw CorpusPatchError()
            }
            array[index] = replacement
        case "add":
            guard index <= array.count, let replacement else {
                throw CorpusPatchError()
            }
            array.insert(replacement, at: index)
        default:
            throw CorpusPatchError()
        }
        return array
    }

    private func appendActivityCoding(
        _ coding: Coding,
        to bundle: inout ModelsR4.Bundle
    ) throws {
        var entries = try #require(bundle.entry)
        let index = try #require(entries.firstIndex(where: {
            if case .provenance = $0.resource {
                return true
            }
            return false
        }))
        guard case .provenance(var provenance)? = entries[index].resource else {
            Issue.record("Fixture lifecycle resource is not Provenance")
            return
        }
        var activity = try #require(provenance.activity)
        activity.coding = (activity.coding ?? []) + [coding]
        provenance.activity = activity
        entries[index].resource = ResourceProxy(with: provenance)
        bundle.entry = entries
    }

    private var corpusDirectory: URL {
        exchangeGraphCorpusDirectory
    }

    private var protocolCatalogURL: URL {
        exchangeGraphCorpusDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("catalog/exchange-protocol.json")
    }
}
