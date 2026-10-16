//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveFHIR
import ModelsR4
import Testing


@Suite
@MainActor
struct FHIRStoreTests {
    private let store = FHIRStore()
    
    
    @Test
    func testInitialState() {
        #expect(store.allergyIntolerances.isEmpty)
        #expect(store.conditions.isEmpty)
        #expect(store.diagnostics.isEmpty)
        #expect(store.encounters.isEmpty)
        #expect(store.immunizations.isEmpty)
        #expect(store.medications.isEmpty)
        #expect(store.observations.isEmpty)
        #expect(store.procedures.isEmpty)
        #expect(store.otherResources.isEmpty)
    }
    
    
    @Test
    func testInsertSingleResource() throws {
        let observation = try ModelsR4Mocks.createObservation()
        let resource = try FHIRResource(resource: observation, displayName: "Test Observation")
        store.insert(resource)

        #expect(store.observations.count == 1)
        #expect(store.observations.first?.displayName == "Test Observation")
        #expect(store.conditions.isEmpty)
    }
    
    
    @Test
    func testInsertMultipleResources() throws {
        let observation1 = try ModelsR4Mocks.createObservation()
        var observation2 = try ModelsR4Mocks.createObservation()
        observation2.id = FHIRPrimitive(FHIRString("observation-id-2"))
        let procedure = try ModelsR4Mocks.createProcedure()
        let medication = ModelsR4Mocks.createMedication()
        let claim = try ModelsR4Mocks.createClaim()

        let resources = [
            try FHIRResource(resource: observation1, displayName: "Observation 1"),
            try FHIRResource(resource: observation2, displayName: "Observation 2"),
            try FHIRResource(resource: procedure, displayName: "Procedure"),
            try FHIRResource(resource: medication, displayName: "Medication"),
            try FHIRResource(resource: claim, displayName: "Claim")
        ]

        try store.insert(contentsOf: resources)
        
        #expect(store.observations.count == 2)
        #expect(store.procedures.count == 1)
        #expect(store.medications.count == 1)
        #expect(store.otherResources.count == 1)
    }
    
    
    @Test
    func testRemoveResource() throws {
        let medication = ModelsR4Mocks.createMedication()
        let resource = try FHIRResource(resource: medication, displayName: "Medication")
            
        store.insert(resource)
        #expect(store.medications.count == 1)
        
        store.removeResource(withID: resource.id)
        #expect(store.medications.isEmpty)
    }
    
    
    @Test
    func testRemoveAllResources() throws {
        let observation1 = try ModelsR4Mocks.createObservation()
        var observation2 = try ModelsR4Mocks.createObservation()
        observation2.id = FHIRPrimitive(FHIRString("observation-id-2"))
        let procedure = try ModelsR4Mocks.createProcedure()
        let medication = ModelsR4Mocks.createMedication()

        let resources = [
            try FHIRResource(resource: observation1, displayName: "Observation 1"),
            try FHIRResource(resource: observation2, displayName: "Observation 2"),
            try FHIRResource(resource: procedure, displayName: "Procedure"),
            try FHIRResource(resource: medication, displayName: "Medication")
        ]
        
        try store.insert(contentsOf: resources)
        store.removeAllResources()

        #expect(store.observations.isEmpty)
        #expect(store.conditions.isEmpty)
        #expect(store.medications.isEmpty)
    }
    
    
    @Test
    func testLoadEmptyBundle() throws {
        let bundle = ModelsR4.Bundle(type: FHIRPrimitive<BundleType>(.transaction))
        try store.load(bundle: bundle)
        #expect(store.allergyIntolerances.isEmpty)
        #expect(store.conditions.isEmpty)
        #expect(store.observations.isEmpty)
        #expect(store.diagnostics.isEmpty)
        #expect(store.encounters.isEmpty)
        #expect(store.immunizations.isEmpty)
        #expect(store.observations.isEmpty)
        #expect(store.procedures.isEmpty)
        #expect(store.otherResources.isEmpty)
    }
    
    
    @Test
    func testLoadBundleWithMultipleResources() throws {
        try store.load(bundle: ModelsR4Mocks.createBundle())
        #expect(store.conditions.count == 1)
        #expect(store.observations.count == 1)
        #expect(store.conditions.first?.fhirId == "condition-id")
        #expect(store.observations.first?.fhirId == "observation-id")
    }
    
    
    @Test
    func testLoadBundleWithInvalidResources() throws {
        var bundle = try ModelsR4Mocks.createBundle()
        let condition = try ModelsR4Mocks.createCondition()
        let emptyEntry = BundleEntry()
        bundle.entry = [
            emptyEntry,
            BundleEntry(resource: .condition(condition))
        ]
        
        try store.load(bundle: bundle)
        #expect(store.conditions.count == 1)
        #expect(store.conditions.first?.id.source == .logicalID("condition-id"))
        #expect(store.otherResources.isEmpty)
    }
    
    
    @Test
    func testLoadBundleWithDuplicateResources() throws {
        #expect(store.isEmpty)
        var bundle = try ModelsR4Mocks.createBundle()
        let condition1 = try ModelsR4Mocks.createCondition()
        let condition2 = try ModelsR4Mocks.createCondition()
        bundle.entry = [
            BundleEntry(resource: .condition(condition1)),
            BundleEntry(resource: .condition(condition2))
        ]
        
        #expect(throws: FHIRStore.StoreError.self) {
            try store.load(bundle: bundle)
        }
        #expect(store.isEmpty)
    }

    @Test("Same identity is atomically replaced while cross-type IDs coexist")
    func upsertUsesCompositeIdentity() throws {
        let originalObservation = try ModelsR4Mocks.createObservation()
        var changedObservation = originalObservation
        changedObservation.status = FHIRPrimitive(.amended)
        let original = try FHIRResource(resource: originalObservation, displayName: "Original")
        let changed = try FHIRResource(resource: changedObservation, displayName: "Changed")

        #expect(store.insert(original))
        #expect(store.insert(changed))
        #expect(store.observations.count == 1)
        #expect(store.observations.first?.displayName == "Changed")
        #expect((store.observations.first?.r4 as? Observation)?.status.value == .amended)

        var patient = try ModelsR4Mocks.createPatient()
        patient.id = originalObservation.id
        let sameLogicalIDOtherType = try FHIRResource(resource: patient, displayName: "Patient")
        #expect(store.insert(sameLogicalIDOtherType))
        #expect(store.count == 2)
    }

    @Test("An id-less Grove-style exchange entry uses fullUrl as stable identity")
    func idLessBundleUsesFullURLIdentity() throws {
        let observation = Observation(
            code: CodeableConcept(),
            status: FHIRPrimitive(.final)
        )
        let fullURL = "urn:uuid:01f43d26-3e29-4d23-b38b-d47f73349be9"
        let bundle = Bundle(
            entry: [
                BundleEntry(
                    fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: fullURL)),
                    resource: .observation(observation)
                )
            ],
            type: FHIRPrimitive(.collection)
        )

        try store.load(bundle: bundle)
        let stored = try #require(store.observations.first)
        #expect(stored.fhirId == nil)
        #expect(stored.id.source == .bundleFullURL(fullURL))
        #expect(!store.insert(stored))
    }

    @Test("A bad bundle leaves prior contents unchanged")
    func bundleReplacementIsAtomicOnUnrecognizedResource() throws {
        let prior = try FHIRResource(resource: ModelsR4Mocks.createObservation(), displayName: "Prior")
        store.insert(prior)
        let invalid = Bundle(
            entry: [BundleEntry(resource: .unrecognized)],
            type: FHIRPrimitive(.collection)
        )

        #expect(throws: FHIRStore.StoreError.unrecognizedResource(entry: 0)) {
            try store.replaceContents(with: invalid)
        }
        #expect(store.count == 1)
        #expect(store.first?.id == prior.id)
    }

    @Test("Duplicate bundle fullUrls fail before any mutation")
    func duplicateFullURLsFailClosed() throws {
        let prior = try FHIRResource(resource: ModelsR4Mocks.createObservation(), displayName: "Prior")
        store.insert(prior)
        let fullURL = "urn:uuid:a9d3b8d1-e55a-4a5b-b903-978c58ab6a12"
        let bundle = Bundle(
            entry: [
                BundleEntry(
                    fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: fullURL)),
                    resource: .observation(Observation(code: CodeableConcept(), status: FHIRPrimitive(.final)))
                ),
                BundleEntry(
                    fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: fullURL)),
                    resource: .condition(Condition(subject: Reference()))
                )
            ],
            type: FHIRPrimitive(.collection)
        )
        #expect(throws: FHIRStore.StoreError.duplicateBundleFullURL(fullURL)) {
            try store.replaceContents(with: bundle)
        }
        #expect(store.count == 1)
        #expect(store.first?.id == prior.id)
    }
}
