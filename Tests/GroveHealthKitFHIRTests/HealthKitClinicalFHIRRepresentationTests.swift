//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HealthKitClinicalFHIRRepresentationTests {
    @Test("Each admitted source release uses its versioned media type with byte-preserved payload")
    func admittedClinicalFHIRRepresentationsAreExact() throws {
        #expect(HealthKitContract.admittedClinicalFHIRReleaseCodes == ["dstu2", "r4"])
        #expect(HealthKitContract.clinicalFHIRContentTypeByRelease == [
            "dstu2": "application/fhir+json; fhirVersion=1.0",
            "r4": "application/fhir+json; fhirVersion=4.0"
        ])
        for sourceRelease in HealthKitContract.admittedClinicalFHIRReleaseCodes.sorted() {
            let payload = Data(" {\"resourceType\":\"Observation\",\"id\":\"\(sourceRelease)\"}\n".utf8)
            let conversion = try makeConversion(releaseCode: sourceRelease, payload: payload)
            let content = try #require(conversion.document.content.first)
            #expect(content.format?.code?.value?.string == HealthKitContract.clinicalFHIRPayloadFormatCode)
            #expect(
                content.attachment.contentType?.value?.string
                    == HealthKitContract.clinicalFHIRContentTypeByRelease[sourceRelease]
            )
            #expect(content.attachment.data?.value?.dataString == payload.base64EncodedString())
        }
    }

    @Test("An unversioned FHIR JSON media type fails graph validation")
    func clinicalFHIRContentTypeIsVersioned() throws {
        #expect(throws: ExchangeGraphError.ruleViolation(.healthkitClinicalFhirRepresentation)) {
            try revalidate(try makeConversion(releaseCode: "dstu2"), contentType: "application/fhir+json")
        }
    }

    @Test("A release outside the admitted DSTU2 and R4 set fails graph validation")
    func unsupportedClinicalFHIRReleaseIsRejected() throws {
        #expect(throws: ExchangeGraphError.ruleViolation(.healthkitClinicalFhirRepresentation)) {
            try revalidate(try makeConversion(releaseCode: "r4"), contentType: "application/fhir+json; fhirVersion=5.0")
        }
        #expect(throws: ExchangeGraphError.ruleViolation(.healthkitClinicalFhirRepresentation)) {
            try revalidate(try makeConversion(releaseCode: "r4"), contentType: nil)
        }
    }

    /// A lab result HealthKit reports in `releaseCode`, DSTU2 or R4, carrying `payload`, converted as the exporter
    /// converts it.
    private func makeConversion(
        releaseCode: String,
        payload: Data = Data(#"{"resourceType":"Observation","id":"clinical"}"#.utf8)
    ) throws -> HealthKitConversionSet {
        let record = try StoredSampleFixtures.clinicalRecord(
            HKClinicalType(.labResultRecord),
            fhirVersion: releaseCode == "dstu2" ? .primaryDSTU2() : .primaryR4(),
            resource: payload,
            facts: GoldenCase.seriesFacts(uuid: 0xF2, duration: 0)
        )
        return try HealthKitAssembly.convert(record, context: HealthKitConversionContext(
            subject: .testPatient,
            converter: ApplicationDevice.test(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: Date(timeIntervalSince1970: 1_755_624_060)
        ))
    }

    /// Validates `conversion`'s graph again with its document's attachment stating `contentType` instead.
    private func revalidate(_ conversion: HealthKitConversionSet, contentType: String?) throws {
        var bundle = conversion.bundle
        var entries = try #require(bundle.entry)
        let documentIndex = try #require(entries.firstIndex {
            if case .documentReference = $0.resource {
                return true
            }
            return false
        })
        guard case .documentReference(var document)? = entries[documentIndex].resource else {
            Issue.record("Clinical graph does not contain its DocumentReference")
            return
        }
        document.content[0].attachment.contentType = contentType?.asFHIRStringPrimitive()
        entries[documentIndex].resource = ResourceProxy(with: document)
        bundle.entry = entries
        _ = try ExchangeGraph(kind: .active, eventIdentifier: conversion.graph.eventIdentifier, bundle: bundle)
    }
}

#endif
