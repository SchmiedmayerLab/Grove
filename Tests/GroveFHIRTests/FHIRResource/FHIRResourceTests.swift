//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIR
import ModelsDSTU2
import ModelsR4
import Testing


@Suite
struct FHIRResourceTests {
    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()

    static let testDate: Date = {
        guard let date = utcDateFormatter.date(from: "2025-01-01") else {
            preconditionFailure("Failed to parse date: Invalid date string format")
        }
        return date
    }()


    @Test
    func testModelsR4ResourceInitialization() throws {
        let mockObservation = try ModelsR4Mocks.createObservation(issuedDate: Self.testDate)

        let resource = try FHIRResource(
            resource: mockObservation,
            displayName: "Test Observation"
        )
        
        #expect(resource.id.version == .r4)
        #expect(resource.id.resourceType == "Observation")
        #expect(resource.id.source == .logicalID("observation-id"))
        #expect(resource.displayName == "Test Observation")
        #expect(resource.resourceType == "Observation")
    }

    @Test
    func testModelsDSTU2ResourceInitialization() throws {
        let mockObservation = try ModelsDSTU2Mocks.createObservation(issuedDate: Self.testDate)

        let resource = try FHIRResource(
            resource: mockObservation,
            displayName: "Test Observation"
        )
        
        #expect(resource.id.version == .dstu2)
        #expect(resource.id.resourceType == "Observation")
        #expect(resource.id.source == .logicalID("observation-id"))
        #expect(resource.displayName == "Test Observation")
        #expect(resource.resourceType == "Observation")
    }

    @Test
    func testModelsR4JSON() throws {
        let observation = ModelsR4.Observation(
            code: CodeableConcept(
                coding: [
                    Coding(code: "test-code".asFHIRStringPrimitive())
                ]
            ),
            id: "test-id".asFHIRStringPrimitive(),
            status: FHIRPrimitive(.final)
        )
        
        let resource = try FHIRResource(
            versionedResource: .r4(observation),
            displayName: "Test"
        )
        
        let jsonString = try resource.json(withConfiguration: [])
        
        let jsonData = jsonString.data(using: .utf8) ?? Data()
        let decoder = JSONDecoder()
        let decodedObservation = try decoder.decode(ModelsR4.Observation.self, from: jsonData)
        
        #expect(decodedObservation.id == observation.id)
        #expect(decodedObservation.code == observation.code)
        #expect(decodedObservation.status == observation.status)
    }
    
    @Test
    func testModelsDSTU2JSON() throws {
        let observation = ModelsDSTU2.Observation(
            code: CodeableConcept(
                coding: [
                    Coding(code: "test-code".asFHIRStringPrimitive())
                ]
            ),
            id: "test-id".asFHIRStringPrimitive(),
            status: FHIRPrimitive(.final)
        )
        
        let resource = try FHIRResource(
            versionedResource: .dstu2(observation),
            displayName: "Test"
        )
        
        let jsonString = try resource.json(withConfiguration: [])
        
        let jsonData = jsonString.data(using: .utf8) ?? Data()
        let decoder = JSONDecoder()
        let decodedObservation = try decoder.decode(ModelsDSTU2.Observation.self, from: jsonData)
        
        #expect(decodedObservation.id == observation.id)
        #expect(decodedObservation.code == observation.code)
        #expect(decodedObservation.status == observation.status)
    }

    @Test
    func missingLogicalIDFailsInsteadOfMintingRandomIdentity() {
        let observation = ModelsR4.Observation(
            code: ModelsR4.CodeableConcept(),
            status: ModelsR4.FHIRPrimitive(.final)
        )

        #expect(throws: FHIRResource.ValidationError.missingStableIdentity(resourceType: "Observation")) {
            try FHIRResource(resource: observation, displayName: "Missing identity")
        }
    }

    @Test("An explicit stable key admits a standalone id-less resource")
    func explicitIdentityAdmitsIDLessResource() throws {
        let observation = ModelsR4.Observation(
            code: ModelsR4.CodeableConcept(),
            status: ModelsR4.FHIRPrimitive(.final)
        )
        let resource = try FHIRResource(
            resource: observation,
            displayName: "Explicit identity",
            identitySource: .explicit("study-a/import-row-7")
        )
        #expect(resource.id.source == .explicit("study-a/import-row-7"))
    }

    @Test("Identity includes FHIR version and resource type and ignores changing content")
    func compositeIdentityAndEquality() throws {
        let r4Observation = ModelsR4.Observation(
            code: ModelsR4.CodeableConcept(),
            id: "shared".asFHIRStringPrimitive(),
            status: ModelsR4.FHIRPrimitive(.final)
        )
        let changedR4Observation = ModelsR4.Observation(
            code: ModelsR4.CodeableConcept(text: "changed".asFHIRStringPrimitive()),
            id: "shared".asFHIRStringPrimitive(),
            status: ModelsR4.FHIRPrimitive(.amended)
        )
        let patient = ModelsR4.Patient(id: "shared".asFHIRStringPrimitive())
        let dstu2Observation = ModelsDSTU2.Observation(
            code: ModelsDSTU2.CodeableConcept(),
            id: "shared".asFHIRStringPrimitive(),
            status: ModelsDSTU2.FHIRPrimitive(.final)
        )
        let original = try FHIRResource(resource: r4Observation, displayName: "Original")
        let changed = try FHIRResource(resource: changedR4Observation, displayName: "Changed")
        let otherType = try FHIRResource(resource: patient, displayName: "Patient")
        let otherVersion = try FHIRResource(resource: dstu2Observation, displayName: "DSTU2")

        #expect(original == changed)
        #expect(original.id != otherType.id)
        #expect(original.id != otherVersion.id)
        #expect(Set([original, changed, otherType, otherVersion]).count == 3)
    }
}
