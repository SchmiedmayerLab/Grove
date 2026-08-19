//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

import FHIRModelsExtensions
import GroveFoundation
import GroveHealthKit
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HKQuantitySampleTests {
    /// One expectation per quantity type whose conversion is a plain
    /// codings + coded-quantity mapping; distinctive behaviors (metadata, devices,
    /// time ranges, components) keep tests of their own.
    struct QuantitySampleExpectation: @unchecked Sendable, CustomStringConvertible {
        // @unchecked: HKUnit is an immutable NSObject and safe to share.
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let value: Double
        let expectedCodings: [Coding]
        let expectedValue: Observation.ValueX

        var description: String { identifier.rawValue }
    }

    var startDate: Date {
        get throws {
            let dateComponents = DateComponents(year: 1891, month: 10, day: 1, hour: 12, minute: 0, second: 0) // Date Stanford University opened (https://www.stanford.edu/about/history/)
            return try #require(Calendar.current.date(from: dateComponents))
        }
    }
    
    var endDate: Date {
        get throws {
            let dateComponents = DateComponents(year: 1891, month: 10, day: 1, hour: 12, minute: 0, second: 42)
            return try #require(Calendar.current.date(from: dateComponents))
        }
    }
    
    func createObservationFrom(
        type quantityType: HKQuantityType,
        quantity: HKQuantity,
        timeRange: Swift.Range<Date>? = nil,
        device: HKDevice? = nil,
        metadata: [String: Any] = [:],
        extensions: [any FHIRExtensionBuilderProtocol] = []
    ) throws -> Observation {
        let quantitySample = HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: try timeRange?.lowerBound ?? startDate,
            end: try timeRange?.upperBound ?? endDate,
            device: device,
            metadata: metadata
        )
        return try #require(quantitySample.resource(subject: Reference(reference: "Patient/example"), extensions: extensions).get(if: Observation.self))
    }
    
    func createCoding(
        code: String,
        display: String,
        system: SupportedCodeSystem
    ) -> Coding {
        Coding(
            code: FHIRPrimitive(stringLiteral: code),
            display: FHIRPrimitive(stringLiteral: display),
            system: FHIRPrimitive(FHIRURI(stringLiteral: system.rawValue))
        )
    }
    
    // MARK: Distinctive Tests

    @Test
    func invalidComponent() throws {
        let startDate = try startDate
        let endDate = try endDate
        let nikeFuel = HKQuantitySample(
            type: HKQuantityType(.nikeFuel),
            quantity: HKQuantity(unit: .count(), doubleValue: 1),
            start: startDate,
            end: endDate
        )
        let correlation: HKCorrelation
        do {
            correlation = try catchingNSException {
                HKCorrelation(
                    type: HKCorrelationType(.bloodPressure),
                    start: startDate,
                    end: endDate,
                    objects: [nikeFuel]
                )
            }
        } catch {
            // it seems that HealthKit sometimes doesn't let us create an invalid sample.
            // in this case we simplu skip the test
            return
        }
        #expect(throws: GroveHealthKitFHIRError.self) {
            try correlation.resource(subject: Reference(reference: "Patient/example"))
        }
    }
    @Test
    func unsupportedType() throws {
        #expect(throws: GroveHealthKitFHIRError.self) {
            try HKVisionPrescription(
                type: .glasses,
                dateIssued: try startDate,
                expirationDate: nil,
                device: nil,
                metadata: nil
            ).resource(subject: Reference(reference: "Patient/example"))
        }
    }
    @Test
    func collectionSampleToResourceProxy() throws {
        func makeSample(numSteps: Int, date: DateComponents) throws -> HKQuantitySample {
            let date = try #require(Calendar.current.date(from: date))
            return HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: Double(numSteps)),
                start: date,
                end: date
            )
        }
        let samples = [
            try makeSample(numSteps: 12, date: .init(year: 2025, month: 1, day: 1, hour: 0)),
            try makeSample(numSteps: 13, date: .init(year: 2025, month: 1, day: 1, hour: 1)),
            try makeSample(numSteps: 14, date: .init(year: 2025, month: 1, day: 1, hour: 2)),
            try makeSample(numSteps: 15, date: .init(year: 2025, month: 1, day: 1, hour: 3)),
            try makeSample(numSteps: 16, date: .init(year: 2025, month: 1, day: 1, hour: 4)),
            try makeSample(numSteps: 17, date: .init(year: 2025, month: 1, day: 1, hour: 5))
        ]
        let resources = try samples.mapIntoResourceProxies(subject: Reference(reference: "Patient/example"))
        #expect(resources.count == samples.count)
        for resource in resources {
            #expect(resource.get(if: Observation.self) != nil)
        }
    }
    @Test
    func timingLivesInEffectivePeriodRatherThanAnExtension() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let startDate = try #require(cal.date(from: .init(year: 1970, month: 1, day: 1, hour: 0, minute: 0, second: 0)))
        let endDate = try #require(cal.date(from: .init(year: 1970, month: 1, day: 1, hour: 0, minute: 15, second: 0)))
        let observation = try createObservationFrom(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 42),
            timeRange: startDate..<endDate,
            extensions: []
        )
        // Epoch seconds used to ride along in a pair of Grove extensions. effective[x]
        // carries the same instants at full precision, so nothing duplicates them.
        guard case let .period(period) = observation.effective else {
            Issue.record("Expected an effectivePeriod")
            return
        }
        // Asserted as instants: the rendering carries the converting machine's offset,
        // so comparing strings would only test where the test runs.
        #expect(try #require(period.start?.value).asNSDate() == startDate)
        #expect(try #require(period.end?.value).asNSDate() == endDate)
        #expect(observation.extension == nil)
    }
    @Test
    func sampleSourceInfo() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let startDate = try #require(cal.date(from: .init(year: 1970, month: 1, day: 1, hour: 0, minute: 0, second: 0)))
        let endDate = try #require(cal.date(from: .init(year: 1970, month: 1, day: 1, hour: 0, minute: 15, second: 0)))
        let device = HKDevice(
            name: "Cerebral Activity Modulator",
            manufacturer: "Lukas Industries",
            model: "A1000",
            hardwareVersion: "X12/49",
            firmwareVersion: "2.1.4",
            softwareVersion: "1.7.9",
            localIdentifier: UUID().uuidString,
            udiDeviceIdentifier: nil
        )
        let observation = try createObservationFrom(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 42),
            timeRange: startDate..<endDate,
            device: device,
            extensions: []
        )
        // The recording hardware is a contained Device referenced from Observation.device;
        // the saving app rides the HL7 observation-gatewayDevice extension. A sample with
        // a device (and no user-entered flag) is automatically recorded.
        #expect(observation.device?.reference?.value?.string == "#sensor-device")
        // An unsaved sample carries no source revision, so there is no gateway app to
        // describe and none is contained — an empty Device would fail its own profile.
        let extensionUrls = Set((observation.extension ?? []).compactMap { $0.url.value?.url.absoluteString })
        #expect(extensionUrls == ["https://grovealliance.org/fhir/core/StructureDefinition/grove-recording-method"])
        let contained = observation.contained ?? []
        let sensor = try #require(
            contained.compactMap { $0.get(if: Device.self) }.first { $0.id?.value?.string == "sensor-device" }
        )
        #expect(sensor.deviceName?.first?.name.value?.string == "Cerebral Activity Modulator")
        #expect(sensor.deviceName?.first?.type.value == .userFriendlyName)
        #expect(sensor.manufacturer?.value?.string == "Lukas Industries")
        #expect(sensor.modelNumber?.value?.string == "A1000")
        #expect(sensor.identifier?.first?.system?.value?.url.absoluteString == "https://grovealliance.org/fhir/sid/device-local-id")
        #expect(sensor.identifier?.first?.value?.value?.string == device.localIdentifier)
        // MDC-coded version slices, per the Personal Health Device IG vocabulary.
        func version(_ mdcCode: String) -> String? {
            sensor.version?
                .first { $0.type?.coding?.first?.code?.value?.string == mdcCode }?
                .value.value?.string
        }
        #expect(version("531974") == "X12/49")
        #expect(version("531976") == "2.1.4")
        #expect(version("531975") == "1.7.9")
        #expect(sensor.version?.first?.type?.coding?.first?.system?.value?.url.absoluteString == "urn:iso:std:iso:11073:10101")
        #expect(!contained.compactMap { $0.get(if: Device.self) }.contains { $0.id?.value?.string == "gateway-device" })
    }
    @Test
    func sampleMetadataExtension() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let startDate = try #require(cal.date(from: .init(year: 1970, month: 1, day: 1, hour: 0, minute: 0, second: 0)))
        let endDate = try #require(cal.date(from: .init(year: 1970, month: 1, day: 1, hour: 0, minute: 15, second: 0)))
        let metadataExternalUUID = UUID()
        let metadataTimeZone = TimeZone.current
        let metadataWeather = HKWeatherCondition.snow
        let observation = try createObservationFrom(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 42),
            timeRange: startDate..<endDate,
            metadata: [
                HKMetadataKeyExternalUUID: metadataExternalUUID.uuidString,
                HKMetadataKeyTimeZone: metadataTimeZone.identifier,
                HKMetadataKeyWeatherCondition: NSNumber(value: metadataWeather.rawValue)
            ]
        )
        let extensions = try #require(observation.extension)
        #expect(Set(extensions.compactMap(\.url)) == [FHIRExtensionURL.metadata.r4])
        // Each surviving entry is its own extension: a key coding plus a typed value.
        // The key never becomes part of the extension URL — every extension URL has to
        // resolve to a StructureDefinition.
        #expect(metadataValue(in: extensions, forKey: HKMetadataKeyExternalUUID)
            == .string(metadataExternalUUID.uuidString.asFHIRStringPrimitive()))
        #expect(metadataValue(in: extensions, forKey: HKMetadataKeyWeatherCondition)
            == .coding(Coding(
                code: "snow".asFHIRStringPrimitive(),
                display: "snow",
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-weather-condition".asFHIRURIPrimitive()
            )))
        // The time zone is routed to the timezone extension on effective[x], so it
        // must not appear as a metadata entry too.
        #expect(metadataValue(in: extensions, forKey: HKMetadataKeyTimeZone) == nil)
        if case let .period(period) = observation.effective {
            let zoneExtension = period.start?.extension?.first {
                $0.url.value?.url.absoluteString == "http://hl7.org/fhir/StructureDefinition/timezone"
            }
            #expect(zoneExtension?.value == .code(FHIRPrimitive(FHIRString(metadataTimeZone.identifier))))
        } else {
            Issue.record("Expected an effectivePeriod")
        }

        // can't unit-test the encoding of the source revision into the extensions,
        // since HKSamples only have a source revision once they're saved to HealthKit, which we can't do here.
    }
    @Test
    func simpleSampleToJson() throws {
        let date = try #require(Calendar.current.date(from: .init(year: 2026, month: 4, day: 21, hour: 12, minute: 7)))
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count() / .minute(), doubleValue: 91),
            start: date,
            end: date
        )
        let resource = try sample.resource(subject: Reference(reference: "Patient/example"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(resource), as: UTF8.self)
        print(json)
    }

    // MARK: Uniform Type Mappings

    @Test(arguments: quantityMappingExpectations)
    func quantityMapping(_ expectation: QuantitySampleExpectation) throws {
        let observation = try createObservationFrom(
            type: HKQuantityType(expectation.identifier),
            quantity: HKQuantity(unit: expectation.unit, doubleValue: expectation.value)
        )
        #expect(observation.code.coding == expectation.expectedCodings)
        #expect(observation.value == expectation.expectedValue)
    }
}


// MARK: Utils

/// The value of the platform-metadata entry for `key`, or `nil` if there is none.
func metadataValue(in extensions: [Extension], forKey key: String) -> Extension.ValueX? {
    for entry in extensions where entry.url == FHIRExtensionURL.metadata.r4 {
        let matchesKey = entry.extension?.contains {
            $0.url == "key" && $0.value == .coding(Coding(
                code: key.asFHIRStringPrimitive(),
                system: GroveFHIRVocabulary.healthKitMetadataKey
            ))
        }
        if matchesKey == true {
            return entry.extension?.first { $0.url == "value" }?.value
        }
    }
    return nil
}


/// Builds a test-expected `Coding` (file-scope so the expectation table can use it).
private func makeCoding(code: String, display: String, system: SupportedCodeSystem) -> Coding {
    Coding(
        code: FHIRPrimitive(stringLiteral: code),
        display: FHIRPrimitive(stringLiteral: display),
        system: FHIRPrimitive(FHIRURI(stringLiteral: system.rawValue))
    )
}

@available(iOS 18, macOS 15, watchOS 11, *)
private let quantityMappingExpectations: [HKQuantitySampleTests.QuantitySampleExpectation] = [
        .init(
            identifier: .bloodGlucose,
            unit: HKUnit(from: "mg/dL"),
            value: 99,
            expectedCodings: [
                makeCoding(
                code: "2339-0",
                display: "Glucose [Mass/volume] in Blood",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBloodGlucose",
                display: "Blood Glucose",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg/dL",
                system: "http://unitsofmeasure.org",
                unit: "mg/dL",
                value: 99.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryBiotin,
            unit: .gramUnit(with: .micro),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "700183008",
                display: "Biotin intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryBiotin",
                display: "Dietary Biotin Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryCaffeine,
            unit: .gramUnit(with: .milli),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "1208604004",
                display: "Caffeine intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryCaffeine",
                display: "Dietary Caffeine Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryCalcium,
            unit: .gramUnit(with: .milli),
            value: 1000,
            expectedCodings: [
                makeCoding(
                code: "230122008",
                display: "Calcium intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryCalcium",
                display: "Dietary Calcium Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1000.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryCarbohydrates,
            unit: .gram(),
            value: 1000,
            expectedCodings: [
                makeCoding(
                code: "788472008",
                display: "Carbohydrate intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryCarbohydrates",
                display: "Dietary Carbohydrates Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 1000.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryChloride,
            unit: .gramUnit(with: .milli),
            value: 2300,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryChloride",
                display: "Dietary Chloride Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 2300.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryCholesterol,
            unit: .gramUnit(with: .milli),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryCholesterol",
                display: "Dietary Cholesterol Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryChromium,
            unit: .gramUnit(with: .micro),
            value: 25,
            expectedCodings: [
                makeCoding(
                code: "890196009",
                display: "Chromium intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryChromium",
                display: "Dietary Chromium Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 25.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryCopper,
            unit: .gramUnit(with: .micro),
            value: 900,
            expectedCodings: [
                makeCoding(
                code: "286615007",
                display: "Copper intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryCopper",
                display: "Dietary Copper Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 900.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryFatMonounsaturated,
            unit: .gram(),
            value: 22,
            expectedCodings: [
                makeCoding(
                code: "226329008",
                display: "Monounsaturated fat intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryFatMonounsaturated",
                display: "Dietary Monounsaturated Fat Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 22.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryFatPolyunsaturated,
            unit: .gram(),
            value: 30,
            expectedCodings: [
                makeCoding(
                code: "226330003",
                display: "Polyunsaturated fat intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryFatPolyunsaturated",
                display: "Dietary Polyunsaturated Fat Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 30.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryFatSaturated,
            unit: .gram(),
            value: 30,
            expectedCodings: [
                makeCoding(
                code: "226328000",
                display: "Saturated fat intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryFatSaturated",
                display: "Dietary Saturated Fat Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 30.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryFatTotal,
            unit: .gram(),
            value: 66,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryFatTotal",
                display: "Dietary Total Fat Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 66.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryFiber,
            unit: .gram(),
            value: 30,
            expectedCodings: [
                makeCoding(
                code: "876831004",
                display: "Plant fiber intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryFiber",
                display: "Dietary Fiber Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 30.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryFolate,
            unit: .gramUnit(with: .micro),
            value: 400,
            expectedCodings: [
                makeCoding(
                code: "792806007",
                display: "Folate and/or folate derivative intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryFolate",
                display: "Dietary Folate Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 400.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryIodine,
            unit: .gramUnit(with: .micro),
            value: 140,
            expectedCodings: [
                makeCoding(
                code: "890199002",
                display: "Iodine intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryIodine",
                display: "Dietary Iodine Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 140.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryIron,
            unit: .gramUnit(with: .milli),
            value: 16,
            expectedCodings: [
                makeCoding(
                code: "286614006",
                display: "Iron intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryIron",
                display: "Dietary Iron Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 16.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryMagnesium,
            unit: .gramUnit(with: .milli),
            value: 400,
            expectedCodings: [
                makeCoding(
                code: "230124009",
                display: "Magnesium intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryMagnesium",
                display: "Dietary Magnesium Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 400.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryManganese,
            unit: .gramUnit(with: .milli),
            value: 2.3,
            expectedCodings: [
                makeCoding(
                code: "890198005",
                display: "Manganese intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryManganese",
                display: "Dietary Manganese Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 2.3.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryMolybdenum,
            unit: .gramUnit(with: .micro),
            value: 45,
            expectedCodings: [
                makeCoding(
                code: "890200004",
                display: "Molybdenum intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryMolybdenum",
                display: "Dietary Molybdenum Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 45.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryPhosphorus,
            unit: .gramUnit(with: .milli),
            value: 1000,
            expectedCodings: [
                makeCoding(
                code: "230123003",
                display: "Phosphorus intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryPhosphorus",
                display: "Dietary Phosphorus Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1000.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryPotassium,
            unit: .gramUnit(with: .milli),
            value: 1000,
            expectedCodings: [
                makeCoding(
                code: "788479004",
                display: "Potassium intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryPotassium",
                display: "Dietary Potassium Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1000.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietarySodium,
            unit: .gramUnit(with: .milli),
            value: 1000,
            expectedCodings: [
                makeCoding(
                code: "1148504005",
                display: "Sodium intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietarySodium",
                display: "Dietary Sodium Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1000.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryNiacin,
            unit: .gramUnit(with: .milli),
            value: 16,
            expectedCodings: [
                makeCoding(
                code: "286583002",
                display: "Niacin intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryNiacin",
                display: "Dietary Niacin Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 16.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryPantothenicAcid,
            unit: .gramUnit(with: .milli),
            value: 5,
            expectedCodings: [
                makeCoding(
                code: "286600006",
                display: "Pantothenic acid intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryPantothenicAcid",
                display: "Dietary Pantothenic Acid Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryProtein,
            unit: .gram(),
            value: 40,
            expectedCodings: [
                makeCoding(
                code: "874875003",
                display: "Protein and/or protein derivative intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryProtein",
                display: "Dietary Protein Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 40.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryRiboflavin,
            unit: .gramUnit(with: .milli),
            value: 1.3,
            expectedCodings: [
                makeCoding(
                code: "286581000",
                display: "Vitamin B2 intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryRiboflavin",
                display: "Dietary Riboflavin Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1.3.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietarySelenium,
            unit: .gramUnit(with: .micro),
            value: 55,
            expectedCodings: [
                makeCoding(
                code: "286616008",
                display: "Selenium intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietarySelenium",
                display: "Dietary Selenium Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 55.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietarySugar,
            unit: .gram(),
            value: 30,
            expectedCodings: [
                makeCoding(
                code: "226459004",
                display: "Sugar intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietarySugar",
                display: "Dietary Sugar Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "g",
                system: "http://unitsofmeasure.org",
                unit: "g",
                value: 30.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryThiamin,
            unit: .gramUnit(with: .milli),
            value: 1.2,
            expectedCodings: [
                makeCoding(
                code: "286579002",
                display: "Vitamin B1 intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryThiamin",
                display: "Dietary Thiamin Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1.2.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminA,
            unit: .gramUnit(with: .micro),
            value: 900,
            expectedCodings: [
                makeCoding(
                code: "286604002",
                display: "Vitamin A intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminA",
                display: "Dietary Vitamin A Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 900.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminB12,
            unit: .gramUnit(with: .micro),
            value: 2.4,
            expectedCodings: [
                makeCoding(
                code: "1144896002",
                display: "Vitamin B12 and/or vitamin B12 derivative intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminB12",
                display: "Dietary Vitamin B12 Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 2.4.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminB6,
            unit: .gramUnit(with: .milli),
            value: 1.5,
            expectedCodings: [
                makeCoding(
                code: "1144810007",
                display: "Vitamin B6 and/or vitamin B6 derivative intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminB6",
                display: "Dietary Vitamin B6 Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 1.5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminC,
            unit: .gramUnit(with: .milli),
            value: 90,
            expectedCodings: [
                makeCoding(
                code: "286586005",
                display: "Vitamin C intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminC",
                display: "Dietary Vitamin C Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 90.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminD,
            unit: .gramUnit(with: .micro),
            value: 20,
            expectedCodings: [
                makeCoding(
                code: "286607009",
                display: "Vitamin D intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminD",
                display: "Dietary Vitamin D Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 20.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminE,
            unit: .gramUnit(with: .milli),
            value: 15,
            expectedCodings: [
                makeCoding(
                code: "286606000",
                display: "Vitamin E intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminE",
                display: "Dietary Vitamin E Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 15.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryVitaminK,
            unit: .gramUnit(with: .micro),
            value: 15,
            expectedCodings: [
                makeCoding(
                code: "430195004",
                display: "Vitamin K intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryVitaminK",
                display: "Dietary Vitamin K Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ug",
                system: "http://unitsofmeasure.org",
                unit: "ug",
                value: 15.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryWater,
            unit: .liter(),
            value: 2,
            expectedCodings: [
                Coding(
                code: "8999-5",
                display: "Fluid intake oral Estimated",
                system: .loincSystem
                ),
                Coding(
                code: "226354008",
                display: "Water intake",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryWater",
                display: "Dietary Water Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "L",
                system: "http://unitsofmeasure.org",
                unit: "L",
                value: 2.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryWater,
            unit: .literUnit(with: .milli),
            value: 2500,
            expectedCodings: [
                Coding(
                code: "8999-5",
                display: "Fluid intake oral Estimated",
                system: .loincSystem
                ),
                Coding(
                code: "226354008",
                display: "Water intake",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryWater",
                display: "Dietary Water Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "L",
                system: "http://unitsofmeasure.org",
                unit: "L",
                value: 2.5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .dietaryZinc,
            unit: .gramUnit(with: .milli),
            value: 11,
            expectedCodings: [
                makeCoding(
                code: "286617004",
                display: "Zinc intake",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDietaryZinc",
                display: "Dietary Zinc Intake",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mg",
                system: "http://unitsofmeasure.org",
                unit: "mg",
                value: 11.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .electrodermalActivity,
            unit: .siemen(),
            value: 0.000001,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierElectrodermalActivity",
                display: "Electrodermal Activity",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "uS",
                system: "http://unitsofmeasure.org",
                unit: "microsiemens",
                value: 1.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .forcedExpiratoryVolume1,
            unit: .liter(),
            value: 3.5,
            expectedCodings: [
                makeCoding(
                code: "20150-9",
                display: "FEV1",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierForcedExpiratoryVolume1",
                display: "Forced Expiratory Volume (1 sec)",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "L",
                system: "http://unitsofmeasure.org",
                unit: "L",
                value: 3.5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .forcedVitalCapacity,
            unit: .liter(),
            value: 5.5,
            expectedCodings: [
                makeCoding(
                code: "19870-5",
                display: "Forced vital capacity [Volume] Respiratory system",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierForcedVitalCapacity",
                display: "Forced Vital Capacity",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "L",
                system: "http://unitsofmeasure.org",
                unit: "L",
                value: 5.5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .inhalerUsage,
            unit: .count(),
            value: 3,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierInhalerUsage",
                display: "Inhaler Usage",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{puff}",
                system: "http://unitsofmeasure.org",
                unit: "puffs",
                value: 3.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .stepCount,
            unit: .count(),
            value: 42,
            expectedCodings: [
                makeCoding(
                code: "55423-8",
                display: "Number of steps in unspecified time Pedometer",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierStepCount",
                display: "Step Count",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{steps}",
                system: "http://unitsofmeasure.org",
                unit: "steps",
                value: 42.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .flightsClimbed,
            unit: .count(),
            value: 10,
            expectedCodings: [
                makeCoding(
                code: "100304-5",
                display: "Flights climbed [#] Reporting Period",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierFlightsClimbed",
                display: "Flights Climbed",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{flight}",
                system: "http://unitsofmeasure.org",
                unit: "flights",
                value: 10.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .heartRate,
            unit: .count().unitDivided(by: .minute()),
            value: 84,
            expectedCodings: [
                Coding(
                code: "8867-4",
                display: "Heart rate",
                system: .loincSystem
                ),
                Coding(
                code: "364075005",
                display: "Heart rate",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierHeartRate",
                display: "Heart Rate",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "/min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "beats/minute",
                value: 84.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .restingHeartRate,
            unit: .count().unitDivided(by: .minute()),
            value: 84,
            expectedCodings: [
                makeCoding(
                code: "40443-4",
                display: "Heart rate --resting",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierRestingHeartRate",
                display: "Resting Heart Rate",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "/min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "beats/minute",
                value: 84.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .walkingHeartRateAverage,
            unit: .count().unitDivided(by: .minute()),
            value: 84,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierWalkingHeartRateAverage",
                display: "Walking Heart Rate Average",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "/min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "beats/minute",
                value: 84.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .walkingAsymmetryPercentage,
            unit: .percent(),
            value: 0.5,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierWalkingAsymmetryPercentage",
                display: "Walking Asymmetry Percentage",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "%",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "%",
                value: 50.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .walkingSpeed,
            unit: HKUnit.meter().unitDivided(by: HKUnit.second()),
            value: 1.5,
            expectedCodings: [
                makeCoding(
                code: "724237005",
                display: "Gait speed",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierWalkingSpeed",
                display: "Walking Speed",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m/s",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m/s",
                value: 1.5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "80404-7",
                display: "R-R interval.standard deviation (Heart rate variability)",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
                display: "Heart Rate Variability SDNN",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "ms",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "ms",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .oxygenSaturation,
            unit: .percent(),
            value: 0.99,
            expectedCodings: [
                makeCoding(
                code: "2708-6",
                display: "Oxygen saturation in Arterial blood",
                system: .loinc
                ),
                makeCoding(
                code: "59408-5",
                display: "Oxygen saturation in Arterial blood by Pulse oximetry",
                system: .loinc
                ),
                Coding(
                code: "431314004",
                display: "Peripheral oxygen saturation",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierOxygenSaturation",
                display: "Oxygen Saturation",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "%",
                system: "http://unitsofmeasure.org",
                unit: "%",
                value: 99.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .peakExpiratoryFlowRate,
            unit: .liter().unitDivided(by: .minute()),
            value: 600,
            expectedCodings: [
                makeCoding(
                code: "33452-4",
                display: "Maximum expiratory gas flow Respiratory system airway",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierPeakExpiratoryFlowRate",
                display: "Peak Expiratory Flow Rate",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "L/min",
                system: "http://unitsofmeasure.org",
                unit: "L/min",
                value: 600.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .peripheralPerfusionIndex,
            unit: .percent(),
            value: 0.05,
            expectedCodings: [
                makeCoding(
                code: "61006-3",
                display: "Perfusion index Tissue by Pulse oximetry",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierPeripheralPerfusionIndex",
                display: "Peripheral Perfusion Index",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "%",
                system: "http://unitsofmeasure.org",
                unit: "%",
                value: 5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .pushCount,
            unit: .count(),
            value: 5,
            expectedCodings: [
                makeCoding(
                code: "96502-0",
                display: "Number of wheelchair pushes per time period",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierPushCount",
                display: "Wheelchair Push Count",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{wheelchair-push}",
                system: "http://unitsofmeasure.org",
                unit: "wheelchair pushes",
                value: 5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .timeInDaylight,
            unit: .minute(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierTimeInDaylight",
                display: "Time in Daylight",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "min",
                system: "http://unitsofmeasure.org",
                unit: "min",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .uvExposure,
            unit: .count(),
            value: 5,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierUVExposure",
                display: "UV Exposure",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{count}",
                system: "http://unitsofmeasure.org",
                unit: "count",
                value: 5.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .vo2Max,
            unit: HKUnit(from: "mL/kg*min"),
            value: 31,
            expectedCodings: [
                makeCoding(
                code: "94122-9",
                display: "Oxygen consumption (VO2)/Body weight [Volume Rate Content] --peak during exercise",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierVO2Max",
                display: "VO2Max",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "mL/min/kg{body_wt}",
                system: "http://unitsofmeasure.org",
                unit: "mL/kg/min",
                value: 31.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .waistCircumference,
            unit: HKUnit(from: "in"),
            value: 38.7,
            expectedCodings: [
                Coding(
                code: "276361009",
                display: "Waist circumference",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierWaistCircumference",
                display: "Waist Circumference",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "cm",
                system: "http://unitsofmeasure.org",
                unit: "cm",
                value: 98.298.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .bodyTemperature,
            unit: .degreeCelsius(),
            value: 37,
            expectedCodings: [
                Coding(
                code: "8310-5",
                display: "Body temperature",
                system: .loincSystem
                ),
                Coding(
                code: "386725007",
                display: "Body temperature",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBodyTemperature",
                display: "Body Temperature",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "Cel",
                system: "http://unitsofmeasure.org",
                unit: "C",
                value: 37.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .basalBodyTemperature,
            unit: .degreeCelsius(),
            value: 37,
            expectedCodings: [
                Coding(
                code: "8310-5",
                display: "Body temperature",
                system: .loincSystem
                ),
                Coding(
                code: "300076005",
                display: "Basal body temperature",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBasalBodyTemperature",
                display: "Basal Body Temperature",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "Cel",
                system: "http://unitsofmeasure.org",
                unit: "C",
                value: 37.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .basalEnergyBurned,
            unit: HKUnit(from: "kcal"),
            value: 1200,
            expectedCodings: [
                makeCoding(
                code: "1285369003",
                display: "Resting energy expenditure",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBasalEnergyBurned",
                display: "Basal Energy Burned",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "kcal",
                system: "http://unitsofmeasure.org",
                unit: "kcal",
                value: 1200.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .bloodAlcoholContent,
            unit: .percent(),
            value: 0.0,
            expectedCodings: [
                makeCoding(
                code: "74859-0",
                display: "Ethanol [Mass/volume] in Blood Estimated from serum or plasma level",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBloodAlcoholContent",
                display: "Blood Alcohol Content",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "%",
                system: "http://unitsofmeasure.org",
                unit: "%",
                value: 0.0.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            value: 0.21,
            expectedCodings: [
                makeCoding(
                code: "41982-0",
                display: "Percentage of body fat Measured",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBodyFatPercentage",
                display: "Body Fat Percentage",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "%",
                system: "http://unitsofmeasure.org",
                unit: "%",
                value: 21.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .bodyMassIndex,
            unit: .count(),
            value: 20,
            expectedCodings: [
                makeCoding(
                code: "39156-5",
                display: "Body mass index (BMI) [Ratio]",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBodyMassIndex",
                display: "BMI",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "kg/m2",
                system: "http://unitsofmeasure.org",
                unit: "kg/m^2",
                value: 20.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .height,
            unit: .meter(),
            value: 1.87,
            expectedCodings: [
                Coding(
                code: "8302-2",
                display: "Body height",
                system: .loincSystem
                ),
                Coding(
                code: "50373000",
                display: "Body height measure",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierHeight",
                display: "Height",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "cm",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "cm",
                value: 187.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            value: 68.7,
            expectedCodings: [
                Coding(
                code: "29463-7",
                display: "Body weight",
                system: .loincSystem
                ),
                Coding(
                code: "27113001",
                display: "Body weight",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierBodyMass",
                display: "Body Mass",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "kg",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "kg",
                value: 68.7.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .leanBodyMass,
            unit: .gramUnit(with: .kilo),
            value: 67,
            expectedCodings: [
                makeCoding(
                code: "91557-9",
                display: "Lean body weight",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierLeanBodyMass",
                display: "Lean Body Mass",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "kg",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "kg",
                value: 67.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .numberOfTimesFallen,
            unit: .count(),
            value: 0,
            expectedCodings: [
                makeCoding(
                code: "298348009",
                display: "Number of falls",
                system: .snomed
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierNumberOfTimesFallen",
                display: "Number of Times Fallen",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{fall}",
                system: "http://unitsofmeasure.org",
                unit: "falls",
                value: 0.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .swimmingStrokeCount,
            unit: .count(),
            value: 10,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierSwimmingStrokeCount",
                display: "Swimming Stroke Count",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "{stroke}",
                system: "http://unitsofmeasure.org",
                unit: "strokes",
                value: 10.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .respiratoryRate,
            unit: .count().unitDivided(by: .minute()),
            value: 18,
            expectedCodings: [
                Coding(
                code: "9279-1",
                display: "Respiratory rate",
                system: .loincSystem
                ),
                Coding(
                code: "86290005",
                display: "Respiratory rate",
                system: .snomedCT
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierRespiratoryRate",
                display: "Respiratory Rate",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "/min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "breaths/minute",
                value: 18.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .activeEnergyBurned,
            unit: .largeCalorie(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "41981-2",
                display: "Calories burned",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierActiveEnergyBurned",
                display: "Active Energy Burned",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "kcal",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "kcal",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .appleExerciseTime,
            unit: .minute(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierAppleExerciseTime",
                display: "Apple Exercise Time",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "min",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .appleMoveTime,
            unit: .minute(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierAppleMoveTime",
                display: "Apple Move Time",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "min",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .physicalEffort,
            unit: HKUnit(from: "kcal/hr*kg"),
            value: 2,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierPhysicalEffort",
                display: "Physical Effort",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "kcal/(kg.h)",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "kcal/(kg.h)",
                value: 2.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .appleStandTime,
            unit: .minute(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierAppleStandTime",
                display: "Apple Stand Time",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "min",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "min",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .appleWalkingSteadiness,
            unit: .percent(),
            value: 0.5,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierAppleWalkingSteadiness",
                display: "Apple Walking Steadiness",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "%",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "%",
                value: 50.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .distanceCycling,
            unit: .meterUnit(with: .kilo),
            value: 1.75,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierDistanceCycling",
                display: "Cycling Distance",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m",
                value: 1750.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .distanceDownhillSnowSports,
            unit: .meter(),
            value: 1750,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierDistanceDownhillSnowSports",
                display: "Downhill Snow Sports Distance",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m",
                value: 1750.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .distanceSwimming,
            unit: .meter(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "93816-7",
                display: "Swimming distance unspecified time",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDistanceSwimming",
                display: "Swimming Distance",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .distanceWalkingRunning,
            unit: .meter(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "55430-3",
                display: "Walking distance unspecified time Pedometer",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierDistanceWalkingRunning",
                display: "Distance Walking/Running",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .distanceWheelchair,
            unit: .meter(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierDistanceWheelchair",
                display: "Wheelchair Distance",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .environmentalAudioExposure,
            unit: .decibelAWeightedSoundPressureLevel(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierEnvironmentalAudioExposure",
                display: "Environmental Audio Exposure",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "dB[SPL]{A}",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "dB(A) SPL",
                value: 100.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .environmentalSoundReduction,
            unit: .decibelAWeightedSoundPressureLevel(),
            value: 25,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierEnvironmentalSoundReduction",
                display: "Environmental Sound Reduction",
                system: .apple
                )
            ],
            // An attenuation is a ratio, so plain `dB` rather than the absolute `dB[SPL]`.
            expectedValue: .quantity(Quantity(
                code: "dB{A}",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "dB(A)",
                value: 25.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .sixMinuteWalkTestDistance,
            unit: .meter(),
            value: 480,
            expectedCodings: [
                makeCoding(
                code: "64098-7",
                display: "Six minute walk test",
                system: .loinc
                ),
                makeCoding(
                code: "HKQuantityTypeIdentifierSixMinuteWalkTestDistance",
                display: "6 Minute Walk Test Distance",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "m",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "m",
                value: 480.asFHIRDecimalPrimitive()
            ))
        ),
        .init(
            identifier: .headphoneAudioExposure,
            unit: .decibelAWeightedSoundPressureLevel(),
            value: 100,
            expectedCodings: [
                makeCoding(
                code: "HKQuantityTypeIdentifierHeadphoneAudioExposure",
                display: "Headphone Audio Exposure",
                system: .apple
                )
            ],
            expectedValue: .quantity(Quantity(
                code: "dB[SPL]{A}",
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "dB(A) SPL",
                value: 100.asFHIRDecimalPrimitive()
            ))
        )
]

#endif
