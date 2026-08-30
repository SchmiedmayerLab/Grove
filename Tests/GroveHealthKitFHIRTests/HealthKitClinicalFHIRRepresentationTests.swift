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
        let conversion = try makeConversion(releaseCode: "dstu2")
        var bundle = conversion.bundle
        var entries = try #require(bundle.entry)
        let documentIndex = try #require(entries.firstIndex(where: {
            if case .documentReference = $0.resource {
                return true
            }
            return false
        }))
        guard case .documentReference(var document)? = entries[documentIndex].resource else {
            Issue.record("Clinical graph does not contain its DocumentReference")
            return
        }
        document.content[0].attachment.contentType =
            "application/fhir+json".asFHIRStringPrimitive()
        entries[documentIndex].resource = ResourceProxy(with: document)
        bundle.entry = entries

        #expect(throws: ExchangeGraphError.ruleViolation(.clinicalFHIRRepresentation)) {
            _ = try ExchangeGraph(
                kind: .active,
                eventIdentifier: conversion.graph.eventIdentifier,
                bundle: bundle
            )
        }
    }

    @Test("A release outside the admitted DSTU2 and R4 set fails before graph emission")
    func unsupportedClinicalFHIRReleaseIsRejected() {
        #expect(throws: ExchangeGraphError.ruleViolation(.clinicalFHIRRepresentation)) {
            _ = try makeConversion(releaseCode: "r5")
        }
    }

    private func makeConversion(
        releaseCode: String,
        payload: Data = Data(#"{"resourceType":"Observation","id":"clinical"}"#.utf8)
    ) throws -> HealthKitDocumentConversion {
        try HealthKitConverter.assembleDocumentGraph(
            for: HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    doubleValue: 60
                ),
                start: Date(timeIntervalSince1970: 1_755_624_000),
                end: Date(timeIntervalSince1970: 1_755_624_600)
            ),
            evidence: HealthKitRecordingEvidence(
                outputRole: "clinical-record",
                format: .fhirResource,
                title: "Clinical FHIR resource",
                payload: payload,
                profiles: [HealthKitContract.clinicalRecordProfile],
                clinicalRecordTypeCode: "lab-result-record",
                clinicalFHIRReleaseCode: releaseCode
            ),
            context: HealthKitConversionContext(
                subject: .testPatient,
                converter: HealthKitApplication(
                    name: "Example Study",
                    bundleIdentifier: "org.grovealliance.example-study",
                    version: "2.0.0 (42)"
                ),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
                conversionInstant: Date(timeIntervalSince1970: 1_755_624_060)
            )
        )
    }
}

#endif
