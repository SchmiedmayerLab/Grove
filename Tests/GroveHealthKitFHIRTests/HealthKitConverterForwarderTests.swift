//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// The deprecated context API's own checks, made before each entry point forwards to the assembly the exporter uses:
/// a native identifier system the deployment reserves, and an ECG's symptom contexts outside the ECG's scope. The
/// rework's final cleanup deletes this suite with `HealthKitConverter+Deprecated.swift`.
@Suite
struct HealthKitConverterForwarderTests {
    /// The test deployment's source-output system, which no native identifier may reuse.
    private static let reservedSystem = ExchangeEventContext.test().identityScope.systems.opaque.sourceOutput

    /// A context disclosing native identifiers under the reserved system, which also authorizes routes.
    private static let reservedContext = HealthKitConversionContext(
        nativeIdentifierDisclosurePolicy: .authorized(system: reservedSystem),
        routeDisclosurePolicy: .authorized
    )

    /// Every record entry point checks the disclosed system first, before the record is read; the retraction checks
    /// it before the catalog refuses a type without outputs, which the retraction itself never reaches.
    @Test("Every record entry point and the retraction refuse a native identifier system the deployment reserves")
    @available(*, deprecated, message: "Exercises the deprecated converter's entry points")
    func everyEntryPointRefusesAReservedNativeSystem() throws {
        let converter = HealthKitConverter()
        let context = Self.reservedContext
        let expected = HealthKitConversionError.reservedIdentifierSystem
        let series = HealthKitHeartbeatSeriesRecord(
            series: try StoredSampleFixtures.seriesSample(
                HKHeartbeatSeriesSample.self,
                sampleType: HKSeriesType.heartbeat(),
                facts: GoldenCase.seriesFacts(uuid: 0xE0, duration: 2)
            ),
            heartbeats: ContentCorpusGrid.heartbeats.map(\.heartbeat)
        )
        let route = HealthKitWorkoutRouteRecord(
            route: try StoredSampleFixtures.seriesSample(
                HKWorkoutRoute.self,
                sampleType: HKSeriesType.workoutRoute(),
                facts: GoldenCase.seriesFacts(uuid: 0xE1, duration: 1)
            ),
            locations: GoldenCase.routeLocations
        )
        let electrocardiogram = try GoldenCase.electrocardiogramRecord(uuid: 0xE2, symptoms: [])
        #expect(throws: expected) { try converter.convert(series, context: context) }
        #expect(throws: expected) { try converter.convert(route, context: context) }
        #expect(throws: expected) { try converter.convert(electrocardiogram, context: context, symptomContexts: []) }
        #expect(throws: expected) {
            try converter.retraction(
                for: HealthKitSourceRecord(uuid: GoldenFixtures.uuid(0xE3), type: .audiogram),
                context: context,
                occurred: .instant(GoldenFixtures.conversionInstant)
            )
        }
        #if !os(watchOS)
        let clinicalRecord = try ExporterGolden.clinicalRecord(
            uuid: 0xE4,
            version: .primaryR4(),
            payload: #"{"resourceType":"Observation","id":"a1c-r4","status":"final"}"#
        )
        let document = try StoredSampleFixtures.stored(
            HKCDADocumentSample(
                data: Data(GoldenCase.clinicalDocumentXML.utf8),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart.addingTimeInterval(1),
                metadata: GoldenFixtures.timeZoneMetadata
            ),
            uuid: GoldenFixtures.uuid(0xE5)
        )
        #expect(throws: expected) { try converter.convert(clinicalRecord, context: context) }
        #expect(throws: expected) { try converter.convert(document, context: context) }
        #endif
    }

    /// A symptom converts under its own event but in the ECG's scope. The context API checks each symptom context's
    /// subject, repository scope and identity scope (its systems, key id and epoch) against the ECG's before it reads
    /// the ECG, so an ECG whose voltages do not validate is refused for the context too.
    @Test("Each ECG symptom context shares the ECG's subject, repository scope and identity scope, checked before the evidence")
    @available(*, deprecated, message: "Exercises the deprecated converter's ECG path, the only one that takes symptom contexts")
    func symptomContextsShareTheECGScope() throws {
        let converter = HealthKitConverter()
        let context = HealthKitConversionContext()
        let symptomEvent = HealthKitConversionContext(conversionInstant: ExchangeEventContext.testInstant.addingTimeInterval(1)).event
        func symptomContext(
            subject: Subject = symptomEvent.subject,
            repositoryScope: BusinessIdentifier = symptomEvent.repositoryScope,
            identityScope: OpaqueIdentityScope = symptomEvent.identityScope
        ) -> HealthKitConversionContext {
            HealthKitConversionContext(event: ExchangeEventContext(
                subject: subject,
                event: symptomEvent.event,
                identityScope: identityScope,
                repositoryScope: repositoryScope,
                application: symptomEvent.application,
                host: symptomEvent.host,
                conversionInstant: symptomEvent.conversionInstant
            ))
        }
        let scope = symptomEvent.identityScope
        let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let mismatched = [
            symptomContext(subject: .logical(.test(.patient, "other"))),
            symptomContext(repositoryScope: try BusinessIdentifier(system: symptomEvent.repositoryScope.system, value: "secondary")),
            symptomContext(identityScope: ExchangeEventContext.test(graphIdentifierSystem: "https://other.example.org/fhir/identifiers").identityScope),
            symptomContext(identityScope: try OpaqueIdentityScope(systems: scope.systems, keyID: "other", epoch: scope.epoch, key: key)),
            symptomContext(identityScope: try OpaqueIdentityScope(systems: scope.systems, keyID: scope.keyID, epoch: EventSequence(2), key: key))
        ]
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xE6, symptoms: [try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xE7))])
        // One voltage fewer than the ECG reports: its evidence does not validate.
        let unvalidated = HealthKitECGRecord(
            electrocardiogram: record.electrocardiogram,
            voltageMeasurements: Array(record.voltageMeasurements.dropLast()),
            correlatedSymptoms: record.correlatedSymptoms
        )
        let expected = HealthKitConversionError.ecgEvidence(.mismatchedSymptomContext)
        for symptomContext in mismatched {
            #expect(throws: expected) { try converter.convert(record, context: context, symptomContexts: [symptomContext]) }
            #expect(throws: expected) { try converter.convert(unvalidated, context: context, symptomContexts: [symptomContext]) }
        }
        #expect(try converter.convert(record, context: context, symptomContexts: [symptomContext()]).companions.count == 1)
    }
}

#endif
