//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import CryptoKit
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


/// Creates the exporter of this disposable UI-test producer, over an in-memory ledger.
///
/// A production app keeps one exporter per participant over a durable ledger, so an exact redelivery reproduces each
/// event; the UI test starts a fresh ledger every time, so each export takes new events.
func makeFHIRTestExporter() throws -> HealthKitFHIRExporter {
    let systemRoot = "https://grovealliance.org/fhir/testing/identifiers/ui-test"
    let systems = try DeploymentIdentifierSystems(
        opaque: fhirTestIdentitySystems(systemRoot: systemRoot),
        event: IdentifierSystem("\(systemRoot)/event"),
        entryNode: IdentifierSystem("\(systemRoot)/entry-node")
    )
    let producer = try ExchangeProducer(
        identityScope: try OpaqueIdentityScope(
            systems: systems,
            keyID: "ui-test",
            epoch: EventSequence(1),
            key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
        ),
        subject: .logical(try BusinessIdentifier(
            system: "https://grovealliance.org/fhir/testing/identifiers/patient",
            value: "example"
        )),
        application: try ApplicationDevice(
            name: "Grove HealthKit FHIR Test App",
            bundleIdentifier: "org.grovealliance.healthkit-fhir-test-app",
            version: "1.0.0",
            build: "1"
        ),
        host: try HostDevice(
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            name: "Grove HealthKit FHIR UI Test Host",
            manufacturer: "Apple",
            modelNumber: "UI Test Device"
        ),
        storage: ExchangeProducer.InMemoryStorage()
    )
    return try HealthKitFHIRExporter(
        producer: producer,
        repositoryScope: try BusinessIdentifier(system: IdentifierSystem("\(systemRoot)/repository"), value: "healthkit")
    )
}


private func fhirTestIdentitySystems(
    systemRoot: String
) throws -> OpaqueIdentitySystems {
    try OpaqueIdentitySystems(
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
