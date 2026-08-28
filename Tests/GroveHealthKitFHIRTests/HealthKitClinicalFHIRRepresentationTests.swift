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
    @Test("The catalog-fixed R4 representation is mandatory on a clinical FHIR document")
    func clinicalFHIRRepresentationIsFixed() throws {
        let conversion = try makeConversion()
        let releaseExtensions = conversion.document.extension?.filter {
            $0.url == HealthKitContract.clinicalFHIRReleaseExtension
        }
        let releaseExtension = try #require(releaseExtensions?.first)
        #expect(releaseExtensions?.count == 1)
        guard case .code(let releaseCode)? = releaseExtension.value else {
            Issue.record("Clinical FHIR release extension is not valueCode")
            return
        }
        #expect(releaseCode.value?.string == HealthKitContract.clinicalFHIRReleaseCode)

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
        document.extension = nil
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

    private func makeConversion() throws -> HealthKitDocumentConversion {
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
                format: .fhirR4Resource,
                title: "Clinical FHIR resource",
                payload: Data(#"{"resourceType":"Observation","id":"clinical-r4"}"#.utf8),
                profiles: [HealthKitContract.clinicalRecordProfile],
                clinicalRecordTypeCode: "lab-result-record",
                clinicalFHIRReleaseCode: HealthKitContract.clinicalFHIRReleaseCode
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
