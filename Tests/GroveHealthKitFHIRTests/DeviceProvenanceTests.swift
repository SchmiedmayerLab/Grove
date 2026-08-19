//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The facts a consumer filters on — the acquisition channel and the recording device's form
/// factor — are denormalised onto the Observation, because a contained Device cannot be
/// reached by a FHIR search. These check both carriers and the inference behind them.
@Suite
struct DeviceProvenanceTests {
    private static let deviceTypeSystem = "https://grovealliance.org/fhir/core/CodeSystem/grove-device-type"

    private static let operatingSystemExpectations: [(productType: String, name: String?)] = [
        ("Watch7,12", "watchOS"),
        ("iPhone17,2", "iOS"),
        ("iPad13,1", "iPadOS"),
        ("RealityDevice14,1", "visionOS"),
        ("Simulator", nil)
    ]

    private func observation(device: HKDevice?) throws -> Observation {
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 42),
            start: .now,
            end: .now,
            device: device,
            metadata: nil
        )
        let resource = try sample.resource(subject: Reference(reference: "Patient/example"))
        return try #require(resource.get(if: Observation.self))
    }

    private func containedSensor(in observation: Observation) throws -> Device {
        try #require(
            (observation.contained ?? [])
                .compactMap { $0.get(if: Device.self) }
                .first { $0.id?.value?.string == "sensor-device" }
        )
    }

    private func formFactorTag(of observation: Observation) -> String? {
        (observation.meta?.tag ?? [])
            .first { $0.system?.value?.url.absoluteString == Self.deviceTypeSystem }?
            .code?.value?.string
    }

    /// Apple's hardware-versioned spellings, a peripheral that names its own form factor,
    /// and the strings nothing may be concluded from.
    @Test(arguments: [
        (manufacturer: "Apple Inc.", model: "Watch7,12", code: "watch"),
        (manufacturer: "Apple Inc.", model: "Watch", code: "watch"),
        (manufacturer: "Apple Inc.", model: "Apple Watch", code: "watch"),
        (manufacturer: "Apple Inc.", model: "iPhone17,2", code: "phone"),
        (manufacturer: "Apple Inc.", model: "iPhone", code: "phone"),
        (manufacturer: "Apple Inc.", model: "RealityDevice14,1", code: "head-mounted"),
        (manufacturer: "Withings", model: "Body Composition Scale", code: "scale"),
        (manufacturer: "Polar Electro", model: "H10 Chest Strap", code: "chest-strap"),
        (manufacturer: "Oura Health", model: "Heritage Ring", code: "ring"),
        (manufacturer: "Fitbit", model: "Charge 6 Band", code: "fitness-band")
    ])
    func inferredFormFactors(manufacturer: String, model: String, code: String) {
        #expect(DeviceFormFactor.code(manufacturer: manufacturer, model: model) == code)
    }

    /// An opaque vendor model number, hardware the value set has no code for, and a
    /// manufacturer whose product merely borrows an Apple prefix.
    @Test(arguments: [
        (manufacturer: "Omron Healthcare", model: "HEM-9200T"),
        (manufacturer: "Apple Inc.", model: "iPad13,1"),
        (manufacturer: "Apple Inc.", model: "MacBookPro18,3"),
        (manufacturer: "Watchdog Systems", model: "Watchdog 2"),
        (manufacturer: "Apple Inc.", model: "")
    ])
    func unknownFormFactors(manufacturer: String, model: String) {
        #expect(DeviceFormFactor.code(manufacturer: manufacturer, model: model) == nil)
    }

    @Test(arguments: Self.operatingSystemExpectations)
    func operatingSystemNames(productType: String, name: String?) {
        #expect(DeviceFormFactor.operatingSystemName(forProductType: productType) == name)
    }

    @Test
    func convertedSampleCarriesTheAcquisitionChannel() throws {
        let observation = try observation(device: nil)
        // Channel granularity: one URI per acquisition path, never per app instance.
        #expect(observation.meta?.source?.value?.url.absoluteString == "https://grovealliance.org/fhir/source/healthkit")
    }

    @Test
    func watchSampleIsTaggedAndTypedAsInferred() throws {
        let observation = try observation(device: HKDevice(
            name: "Apple Watch",
            manufacturer: "Apple Inc.",
            model: "Watch7,12",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        ))
        #expect(formFactorTag(of: observation) == "watch")
        let type = try #require(try containedSensor(in: observation).type)
        #expect(type.coding?.first?.code?.value?.string == "watch")
        #expect(type.coding?.first?.system?.value?.url.absoluteString == Self.deviceTypeSystem)
        // HealthKit reports no form factor, so the code is a guess and says so.
        let inferred = try #require(type.coding?.first?.extension?.first)
        #expect(inferred.url.value?.url.absoluteString == "https://grovealliance.org/fhir/core/StructureDefinition/grove-inferred-value")
        #expect(inferred.value == .boolean(true))
    }

    /// An absent tag and an `unknown` one must not be conflated: a search for everything
    /// that is not a watch may not sweep up the devices nobody could classify.
    @Test
    func anUnrecognizedDeviceIsLeftUntagged() throws {
        let observation = try observation(device: HKDevice(
            name: "Blood Pressure Monitor",
            manufacturer: "Omron Healthcare",
            model: "HEM-9200T",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        ))
        #expect(formFactorTag(of: observation) == nil)
        #expect(try containedSensor(in: observation).type == nil)
    }

    @Test
    func aSampleWithoutADeviceIsLeftUntagged() throws {
        #expect(formFactorTag(of: try observation(device: nil)) == nil)
    }
}

#endif
