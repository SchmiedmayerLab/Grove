//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import Foundation
import GroveFHIRContract
import GroveHealthKitFHIR
import HealthKit
import ModelsR4


final class HealthKitManager: Sendable {
    let healthStore: HKHealthStore?
    
    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            healthStore = nil
        }
    }
    
    func requestStepAuthorization() async throws {
        try await requestReadWriteAuthorization(for: [.stepCount])
    }
    
    func requestReadWriteAuthorization(for identifiers: [HKQuantityTypeIdentifier]) async throws {
        guard let healthStore else {
            throw HKError(.errorHealthDataUnavailable)
        }
        let sampleTypes = Set(identifiers.map { HKQuantityType($0) })
        try await healthStore.requestAuthorization(toShare: sampleTypes, read: sampleTypes)
    }
    
    func readSamples(
        for identifier: HKQuantityTypeIdentifier,
        sorted sortDescriptors: [SortDescriptor<HKQuantitySample>] = [],
        limit: Int? = nil
    ) async throws -> [HKQuantitySample] {
        guard let healthStore else {
            throw HKError(.errorHealthDataUnavailable)
        }
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: sortDescriptors,
            limit: limit ?? HKObjectQueryNoLimit
        )
        return try await query.result(for: healthStore)
    }
    
    func writeSteps(startDate: Date, endDate: Date, steps: Double) async throws {
        guard let healthStore,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HKError(.errorHealthDataUnavailable)
        }
        let stepsSample = HKQuantitySample(
            type: stepType,
            quantity: HKQuantity(unit: HKUnit.count(), doubleValue: steps),
            start: startDate,
            end: endDate
        )
        try await healthStore.save(stepsSample)
    }
}


/// Creates an isolated exchange event for this disposable UI-test producer.
///
/// A production app persists its producer UUID and next sequence before conversion and reuses the
/// complete event identifier for an exact retry. The UI test deliberately receives the sequence so
/// each source record/version remains one immutable event rather than sharing one Bundle identity.
func makeFHIRTestContext(
    sequence: UInt64,
    conversionInstant: Date
) throws -> HealthKitConversionContext {
    let patientIdentifier = try BusinessIdentifier(
        system: "https://grovealliance.org/fhir/testing/identifiers/patient",
        value: "example"
    )
    let subject = Reference(
        identifier: patientIdentifier.fhirIdentifier,
        type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
    )
    let systemRoot = "https://grovealliance.org/fhir/testing/identifiers/ui-test"
    return HealthKitConversionContext(
        subject: subject,
        subjectIdentity: patientIdentifier,
        converter: HealthKitApplication(
            name: "Grove HealthKit FHIR Test App",
            bundleIdentifier: "org.grovealliance.healthkit-fhir-test-app",
            version: "1.0.0 (1)"
        ),
        converterHost: HealthKitHostDevice(
            sourceDeviceToken: "grove-healthkit-fhir-ui-test-host",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            name: "Grove HealthKit FHIR UI Test Host",
            manufacturer: "Apple",
            modelNumber: "UI Test Device"
        ),
        eventIdentifier: try ExchangeEventIdentifier(
            system: IdentifierSystem("\(systemRoot)/event"),
            producerInstance: UUID(uuid: (
                0x1f, 0x5c, 0x58, 0xaa, 0x6e, 0xc6, 0x4e, 0x79,
                0xa6, 0x82, 0x82, 0x9a, 0x9d, 0xeb, 0xd3, 0xf5
            )),
            sequence: sequence
        ),
        entryNodeIdentifierSystem: try IdentifierSystem("\(systemRoot)/entry-node"),
        identityScope: try PseudonymousIdentityScope(
            systems: fhirTestIdentitySystems(systemRoot: systemRoot),
            keyID: "ui-test",
            epoch: 1,
            key: Data(repeating: 0x42, count: 32)
        ),
        repositoryScope: try BusinessIdentifier(
            system: "\(systemRoot)/repository",
            value: "healthkit"
        ),
        sourceActor: .application,
        conversionInstant: conversionInstant
    )
}


private func fhirTestIdentitySystems(
    systemRoot: String
) throws -> PseudonymousIdentitySystems {
    try PseudonymousIdentitySystems(
        sourceRecord: IdentifierSystem("\(systemRoot)/source-record/test/1"),
        sourceOutput: IdentifierSystem("\(systemRoot)/source-output/test/1"),
        writerRecord: IdentifierSystem("\(systemRoot)/writer-record/test/1"),
        providerRecord: IdentifierSystem("\(systemRoot)/provider-record/test/1"),
        providerOutput: IdentifierSystem("\(systemRoot)/provider-output/test/1"),
        sourceArtifact: IdentifierSystem("\(systemRoot)/source-artifact/test/1"),
        providerArtifact: IdentifierSystem("\(systemRoot)/provider-artifact/test/1"),
        sourceContext: IdentifierSystem("\(systemRoot)/source-context/test/1"),
        recordingDevice: IdentifierSystem("\(systemRoot)/recording-device/test/1"),
        deviceSnapshot: IdentifierSystem("\(systemRoot)/device-snapshot/test/1")
    )
}
