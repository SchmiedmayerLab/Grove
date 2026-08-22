//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// The converter suite intentionally covers the complete generated HealthKit catalog in one matrix.
// swiftlint:disable file_length function_body_length type_body_length

import Foundation
import GroveFHIRContract
import GroveHealthKit
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HealthKitFHIRConverterTests {
    enum QuantityCase: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case activeEnergy
        case basalBodyTemperature
        case bodyFatPercentage
        case bodyHeight
        case bodyMassIndex
        case bodyTemperature
        case bodyWeight
        case dietaryEnergy
        case distanceCrossCountrySkiing
        case distanceCycling
        case distanceDownhillSnowSports
        case distancePaddleSports
        case distanceRowing
        case distanceSkatingSports
        case distanceSwimming
        case distanceWalkingRunning
        case distanceWheelchair
        case heartRate
        case heartRateVariabilitySDNN
        case oxygenSaturation
        case respiratoryRate
        case stepCount
        case vo2Max
        case walkingSpeed

        var testDescription: String { rawValue }

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .activeEnergy: .activeEnergyBurned
            case .basalBodyTemperature: .basalBodyTemperature
            case .bodyFatPercentage: .bodyFatPercentage
            case .bodyHeight: .height
            case .bodyMassIndex: .bodyMassIndex
            case .bodyTemperature: .bodyTemperature
            case .bodyWeight: .bodyMass
            case .dietaryEnergy: .dietaryEnergyConsumed
            case .distanceCrossCountrySkiing: .distanceCrossCountrySkiing
            case .distanceCycling: .distanceCycling
            case .distanceDownhillSnowSports: .distanceDownhillSnowSports
            case .distancePaddleSports: .distancePaddleSports
            case .distanceRowing: .distanceRowing
            case .distanceSkatingSports: .distanceSkatingSports
            case .distanceSwimming: .distanceSwimming
            case .distanceWalkingRunning: .distanceWalkingRunning
            case .distanceWheelchair: .distanceWheelchair
            case .heartRate: .heartRate
            case .heartRateVariabilitySDNN: .heartRateVariabilitySDNN
            case .oxygenSaturation: .oxygenSaturation
            case .respiratoryRate: .respiratoryRate
            case .stepCount: .stepCount
            case .vo2Max: .vo2Max
            case .walkingSpeed: .walkingSpeed
            }
        }

        var sourceUnit: HKUnit {
            switch self {
            case .activeEnergy, .dietaryEnergy: .kilocalorie()
            case .basalBodyTemperature, .bodyTemperature: .degreeCelsius()
            case .bodyHeight: .meterUnit(with: .centi)
            case .bodyMassIndex: .count()
            case .bodyWeight: .gramUnit(with: .kilo)
            case .distanceCrossCountrySkiing, .distanceCycling, .distanceDownhillSnowSports,
                 .distancePaddleSports, .distanceRowing, .distanceSkatingSports,
                 .distanceSwimming, .distanceWalkingRunning, .distanceWheelchair:
                .meter()
            case .heartRate, .respiratoryRate: .count().unitDivided(by: .minute())
            case .heartRateVariabilitySDNN: .secondUnit(with: .milli)
            case .bodyFatPercentage, .oxygenSaturation: .percent()
            case .stepCount: .count()
            case .vo2Max:
                .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
            case .walkingSpeed: .meter().unitDivided(by: .second())
            }
        }

        var sourceValue: Double {
            switch self {
            case .activeEnergy: 120
            case .basalBodyTemperature: 36.5
            case .bodyFatPercentage: 0.223
            case .bodyHeight: 176
            case .bodyMassIndex: 22.1
            case .bodyTemperature: 37.1
            case .bodyWeight: 68.4
            case .dietaryEnergy: 540
            case .distanceCrossCountrySkiing, .distanceCycling, .distanceDownhillSnowSports,
                 .distancePaddleSports, .distanceRowing, .distanceSkatingSports,
                 .distanceSwimming, .distanceWalkingRunning, .distanceWheelchair:
                842
            case .heartRate: 72
            case .heartRateVariabilitySDNN: 48
            case .oxygenSaturation: 0.975
            case .respiratoryRate: 15
            case .stepCount: 431
            case .vo2Max: 42.5
            case .walkingSpeed: 1.35
            }
        }

        var contract: HealthKitFHIRObservationContract {
            switch self {
            case .activeEnergy: .init(shared: GroveFHIRMeasurementCatalog.activeEnergy)
            case .basalBodyTemperature: .init(shared: GroveFHIRMeasurementCatalog.basalBodyTemperature)
            case .bodyFatPercentage: .init(shared: GroveFHIRMeasurementCatalog.bodyFatPercentage)
            case .bodyHeight: .init(shared: GroveFHIRMeasurementCatalog.bodyHeight)
            case .bodyMassIndex: .bodyMassIndex
            case .bodyTemperature: .init(shared: GroveFHIRMeasurementCatalog.bodyTemperature)
            case .bodyWeight: .init(shared: GroveFHIRMeasurementCatalog.bodyWeight)
            case .dietaryEnergy: .init(shared: GroveFHIRMeasurementCatalog.dietaryEnergy)
            case .distanceCrossCountrySkiing, .distanceCycling, .distanceDownhillSnowSports,
                 .distancePaddleSports, .distanceRowing, .distanceSkatingSports,
                 .distanceSwimming, .distanceWalkingRunning, .distanceWheelchair:
                .init(shared: GroveFHIRMeasurementCatalog.distance)
            case .heartRate: .init(shared: GroveFHIRMeasurementCatalog.heartRate)
            case .heartRateVariabilitySDNN: .init(shared: GroveFHIRMeasurementCatalog.heartRateVariabilitySdnn)
            case .oxygenSaturation: .init(shared: GroveFHIRMeasurementCatalog.oxygenSaturation)
            case .respiratoryRate: .init(shared: GroveFHIRMeasurementCatalog.respiratoryRate)
            case .stepCount: .init(shared: GroveFHIRMeasurementCatalog.stepCount)
            case .vo2Max: .init(shared: GroveFHIRMeasurementCatalog.vo2Max)
            case .walkingSpeed: .init(shared: GroveFHIRHealthKitMeasurementCatalog.walkingSpeed)
            }
        }
    }

    enum SleepCase: Int, CaseIterable, CustomTestStringConvertible, Sendable {
        case inBed = 0
        case asleepUnspecified = 1
        case awake = 2
        case light = 3
        case deep = 4
        case rem = 5

        var testDescription: String { expectedCode }

        var expectedCode: String {
            switch self {
            case .inBed: "in-bed"
            case .asleepUnspecified: "asleep-unspecified"
            case .awake: "awake"
            case .light: "light"
            case .deep: "deep"
            case .rem: "rem"
            }
        }

        var expectedSourceCode: String {
            switch self {
            case .inBed: "inBed"
            case .asleepUnspecified: "asleepUnspecified"
            case .awake: "awake"
            case .light: "asleepCore"
            case .deep: "asleepDeep"
            case .rem: "asleepREM"
            }
        }
    }

    private let converter = HealthKitFHIRConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private var context: HealthKitFHIRConversionContext {
        HealthKitFHIRConversionContext(
            subject: Reference(reference: "Patient/example"),
            converter: HealthKitFHIRApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
    }

    private func quantitySample(
        _ type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        interval: TimeInterval = 60,
        device: HKDevice? = nil,
        metadata: [String: Any] = [:]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(type),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: timestamp,
            end: timestamp.addingTimeInterval(interval),
            device: device,
            metadata: metadata
        )
    }

    @Test("Every supported quantity emits its exact shared and adapter profile", arguments: QuantityCase.allCases)
    func supportedQuantity(testCase: QuantityCase) throws {
        let sample = quantitySample(
            testCase.identifier,
            unit: testCase.sourceUnit,
            value: testCase.sourceValue
        )
        let conversion = try converter.convert(sample, context: context)
        let codings = try #require(conversion.observation.code.coding)
        let code = try #require(codings.first)
        let quantity: Quantity = try #require({
            guard case .quantity(let quantity) = conversion.observation.value else {
                return nil
            }
            return quantity
        }())

        let profileClaims = try #require(conversion.observation.meta?.profile)
        #expect(profileClaims == testCase.contract.profiles)
        #expect(profileClaims.count == GroveFHIRProfileClaims.observationAdapterCardinality)
        #expect(GroveFHIRProfileClaims.observationAdapterProfiles.contains(GroveFHIRProfile.healthkitObservation))
        if testCase != .bodyMassIndex {
            #expect(profileClaims.allSatisfy { !GroveFHIRProfileClaims.forbiddenExplicitProfiles.contains($0) })
        }
        #expect(code.system?.value?.url.absoluteString == testCase.contract.code.system)
        #expect(code.code?.value?.string == testCase.contract.code.code)
        #expect(codings.count == 2)
        #expect(codings[1].system == GroveFHIRCanonical.healthKitSourceType)
        #expect(codings[1].code?.value?.string == testCase.identifier.rawValue)
        #expect(quantity.system?.value?.url.absoluteString == testCase.contract.quantity?.system)
        #expect(quantity.code?.value?.string == testCase.contract.quantity?.code)
        #expect(conversion.observation.effective?.isPeriod == (testCase.contract.effective == .period))
        if testCase == .oxygenSaturation {
            #expect(quantity.value?.value?.decimal.description == "97.5")
        }
        if testCase == .bodyFatPercentage {
            #expect(quantity.value?.value?.decimal.description == "22.3")
        }
    }

    @Test("Every HealthKit sleep-stage value maps to the shared code system", arguments: SleepCase.allCases)
    func sleepStage(testCase: SleepCase) throws {
        let sample = HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: testCase.rawValue,
            start: timestamp,
            end: timestamp.addingTimeInterval(1_800)
        )
        let observation = try converter.convert(sample, context: context).observation
        let value: CodeableConcept = try #require({
            guard case .codeableConcept(let concept) = observation.value else {
                return nil
            }
            return concept
        }())
        let codings = try #require(value.coding)

        #expect(observation.meta?.profile == [
            GroveFHIRProfile.groveMobileSleepStage,
            GroveFHIRProfile.healthkitObservation
        ])
        #expect(codings.count == 2)
        #expect(codings[0].system?.value?.url.absoluteString == GroveFHIRCanonical.sleepStageCodeSystem.value?.url.absoluteString)
        #expect(codings[0].code?.value?.string == testCase.expectedCode)
        #expect(codings[1].system == GroveFHIRCanonical.healthKitSleepAnalysis)
        #expect(codings[1].code?.value?.string == testCase.expectedSourceCode)
        #expect(GroveFHIRMeasurementCatalog.sleepStage.allowedValues.contains(testCase.expectedCode))
    }

    @Test
    func bloodPressureUsesBothRequiredComponents() throws {
        let systolic = quantitySample(.bloodPressureSystolic, unit: .millimeterOfMercury(), value: 120)
        let diastolic = quantitySample(.bloodPressureDiastolic, unit: .millimeterOfMercury(), value: 80)
        let sample = HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: timestamp,
            end: timestamp.addingTimeInterval(60),
            objects: [systolic, diastolic]
        )
        let observation = try converter.convert(sample, context: context).observation

        #expect(observation.meta?.profile == [
            GroveFHIRProfile.groveMobileBloodPressure,
            GroveFHIRProfile.healthkitObservation
        ])
        #expect(observation.value == nil)
        #expect(observation.component?.compactMap { $0.code.coding?.first?.code?.value?.string }.sorted() == ["8462-4", "8480-6"])
        #expect(observation.component?.allSatisfy {
            guard case .quantity(let quantity) = $0.value else {
                return false
            }
            return quantity.system?.value?.url.absoluteString == "http://unitsofmeasure.org"
                && quantity.code?.value?.string == "mm[Hg]"
        } == true)
    }

    @Test
    func graphHasCompleteDeterministicEntryIdentitiesAndNoSyntheticResourceIDs() throws {
        let sample = quantitySample(
            .heartRate,
            unit: .count().unitDivided(by: .minute()),
            value: 72,
            device: HKDevice(
                name: "Apple Watch",
                manufacturer: "Apple Inc.",
                model: "Watch7,12",
                hardwareVersion: "Watch7,12",
                firmwareVersion: "1.0",
                softwareVersion: "26.2.1",
                localIdentifier: "local-device-id",
                udiDeviceIdentifier: "udi-device-id"
            )
        )
        var attributedContext = context
        attributedContext = HealthKitFHIRConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            converterWasGateway: true,
            conversionInstant: timestamp
        )
        let first = try converter.convert(sample, context: attributedContext)
        let second = try converter.convert(sample, context: attributedContext)
        let entries = try #require(first.bundle.entry)

        #expect(first.bundle.id == nil)
        #expect(first.observation.id == nil)
        #expect(first.recordingDevice?.id == nil)
        #expect(first.converterApplication.id == nil)
        #expect(first.provenance.id == nil)
        #expect(first.sourceIdentifier.system == GroveFHIRCanonical.healthKitObjectIdentifier)
        #expect(first.sourceIdentifier.value?.value?.string == sample.uuid.uuidString.lowercased())
        #expect(first.bundle.meta?.profile == [GroveFHIRProfile.groveMobileExchangeBundle])
        #expect(first.provenance.meta?.profile == [GroveFHIRHealthKitCatalog.conversionProvenanceProfile])
        #expect(first.bundle.identifier == first.graphIdentifiers.bundle.fhirIdentifier)
        #expect(entries.compactMap(\.fullUrl) == second.bundle.entry?.compactMap(\.fullUrl))
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { entry in
            let identityExtensions = entry.extension?.filter {
                $0.url == GroveFHIRExchangeContract.entryIdentifierExtension
            }
            return entry.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true
                && identityExtensions?.count == 1
        })

        let fullURLs = Set(entries.compactMap { $0.fullUrl?.value?.url.absoluteString })
        let targetReference = first.provenance.target.first?.reference?.value?.string
        let assemblerReference = first.provenance.agent.first?.who.reference?.value?.string
        let sourceEntities = try #require(first.provenance.entity)
        let sourceEntity = try #require(sourceEntities.first)
        let observationURL = try GroveFHIRExchangeIdentity.fullURL(for: first.graphIdentifiers.observation)
        #expect(first.observation.device.flatMap { $0.reference?.value?.string }.map(fullURLs.contains) == true)
        #expect(targetReference == observationURL)
        #expect(assemblerReference.map(fullURLs.contains) == true)
        #expect(sourceEntities.count == 1)
        #expect(sourceEntity.role == FHIRPrimitive(.source))
        #expect(sourceEntity.what.reference == nil)
        #expect(sourceEntity.what.identifier == first.sourceIdentifier)
        #expect(first.recordingDevice?.identifier == nil)
        #expect(first.recordingDevice?.udiCarrier == nil)
    }

    @Test
    func repositoryIDsAndAuthorizedDeviceNamespaceAreOnlyAppliedExplicitly() throws {
        let sample = quantitySample(
            .bodyMass,
            unit: .gramUnit(with: .kilo),
            value: 68.4,
            device: HKDevice(
                name: "Scale",
                manufacturer: "Example",
                model: "S1",
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: "1.0",
                localIdentifier: "scale-42",
                udiDeviceIdentifier: "globally-identifying-udi"
            )
        )
        let explicitContext = HealthKitFHIRConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: timestamp,
            recordingDeviceIdentifierSystem: "https://study.example.org/fhir/identifiers/recording-device",
            repositoryIDs: HealthKitFHIRRepositoryIDs(
                bundle: try GroveFHIRRepositoryID("bundle-1"),
                observation: try GroveFHIRRepositoryID("observation-1"),
                recordingDevice: try GroveFHIRRepositoryID("device-1"),
                converterApplication: try GroveFHIRRepositoryID("application-1"),
                provenance: try GroveFHIRRepositoryID("provenance-1")
            )
        )
        let conversion = try converter.convert(sample, context: explicitContext)

        #expect(conversion.bundle.id?.value?.string == "bundle-1")
        #expect(conversion.observation.id?.value?.string == "observation-1")
        #expect(conversion.recordingDevice?.id?.value?.string == "device-1")
        #expect(conversion.converterApplication.id?.value?.string == "application-1")
        #expect(conversion.provenance.id?.value?.string == "provenance-1")
        #expect(conversion.recordingDevice?.identifier?.first?.system?.value?.url.absoluteString == "https://study.example.org/fhir/identifiers/recording-device")
        #expect(conversion.recordingDevice?.identifier?.first?.value?.value?.string == "scale-42")
        #expect(conversion.recordingDevice?.udiCarrier == nil)
    }

    @Test
    func authorizedUDIDisclosureIsIndependentFromLocalIdentifierDisclosure() throws {
        let sample = quantitySample(
            .bodyMass,
            unit: .gramUnit(with: .kilo),
            value: 68.4,
            device: HKDevice(
                name: "Scale",
                manufacturer: "Example",
                model: "S1",
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: "1.0",
                localIdentifier: "deployment-local-id",
                udiDeviceIdentifier: "authorized-udi"
            )
        )
        let authorizedContext = HealthKitFHIRConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: timestamp,
            udiDisclosurePolicy: .authorizedUDI
        )
        let conversion = try converter.convert(sample, context: authorizedContext)

        #expect(conversion.recordingDevice?.identifier == nil)
        #expect(conversion.recordingDevice?.udiCarrier?.first?.deviceIdentifier?.value?.string == "authorized-udi")
    }

    @Test
    func typedMetadataDoesNotInferUnknownFacts() throws {
        let automatic = try converter.convert(
            quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4),
            context: context
        )
        #expect(automatic.observation.extension?.contains {
            $0.url == GroveFHIRCanonical.recordingMethod
        } != true)
        #expect(automatic.sourceAuthor == nil)

        let manual = try converter.convert(
            quantitySample(
                .bodyMass,
                unit: .gramUnit(with: .kilo),
                value: 68.4,
                metadata: [HKMetadataKeyWasUserEntered: true]
            ),
            context: context
        )
        #expect(manual.observation.extension?.contains {
            $0.url == GroveFHIRCanonical.recordingMethod
        } == true)
        #expect(manual.observation.performer == nil)
    }

    @Test
    func heartRateMetadataIsAllowlistedAndUnknownValuesFailClosed() throws {
        let valid = try converter.convert(
            quantitySample(
                .heartRate,
                unit: .count().unitDivided(by: .minute()),
                value: 72,
                metadata: [
                    HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1),
                    HKMetadataKeyExternalUUID: "not-copied"
                ]
            ),
            context: context
        )
        #expect(valid.observation.component?.contains {
            $0.code.coding?.first?.code?.value?.string == HKMetadataKeyHeartRateMotionContext
        } == true)
        #expect(valid.observation.extension?.contains {
            $0.url.value?.url.absoluteString.contains("metadata") == true
        } != true)

        let invalid = quantitySample(
            .heartRate,
            unit: .count().unitDivided(by: .minute()),
            value: 72,
            metadata: [HKMetadataKeyHeartRateMotionContext: NSNumber(value: 99)]
        )
        #expect(throws: GroveHealthKitFHIRError.unsupportedMetadataValue(
            key: HKMetadataKeyHeartRateMotionContext,
            value: "99"
        )) {
            try converter.convert(invalid, context: context)
        }
    }

    @Test
    func glucoseConvertsWithoutSpecimenAndWithoutHealthConnectOnlyProfiles() throws {
        let sample = quantitySample(
            .bloodGlucose,
            unit: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)),
            value: 100
        )
        let observation = try converter.convert(sample, context: context).observation

        #expect(observation.meta?.profile == [
            GroveFHIRProfile.groveMobileBloodGlucoseUnspecifiedSpecimen,
            GroveFHIRProfile.healthkitObservation
        ])
        #expect(observation.specimen == nil)
        let quantity: Quantity = try #require({
            guard case .quantity(let quantity) = observation.value else {
                return nil
            }
            return quantity
        }())
        #expect(quantity.code?.value?.string == "mg/dL")
        #expect(quantity.value?.value?.decimal.description == "100")
    }

    @Test
    func catalogIsACompleteUniqueMatrixForKnownHealthKitTypes() {
        let rows = HealthKitFHIRCatalog.entries
        let sourceIdentifiers = rows.map { $0.sourceTypeIdentifier }
        var expectedIdentifierList: [String] = SampleType<HKQuantitySample>.allKnownQuantities.map {
            $0.identifier.rawValue
        }
        expectedIdentifierList.append(contentsOf: SampleType<HKCategorySample>.allKnownCategories.map {
            $0.identifier.rawValue
        })
        expectedIdentifierList.append(contentsOf: SampleType<HKCorrelation>.allKnownCorrelations.map {
            $0.identifier.rawValue
        })
        // HKClinicalRecord is unavailable on watchOS. The generated cross-platform
        // inventory remains authoritative and retains these complete catalog tokens.
        expectedIdentifierList.append(contentsOf: [
            "HKClinicalTypeIdentifierAllergyRecord",
            "HKClinicalTypeIdentifierClinicalNoteRecord",
            "HKClinicalTypeIdentifierConditionRecord",
            "HKClinicalTypeIdentifierCoverageRecord",
            "HKClinicalTypeIdentifierImmunizationRecord",
            "HKClinicalTypeIdentifierLabResultRecord",
            "HKClinicalTypeIdentifierMedicationRecord",
            "HKClinicalTypeIdentifierProcedureRecord",
            "HKClinicalTypeIdentifierVitalSignRecord"
        ])
        expectedIdentifierList.append(contentsOf: SampleType<HKQuantitySample>.otherSampleTypes.map { $0.id })
        // The frozen catalog also inventories platform identifiers that are not sample types:
        // characteristics, documents, medication concepts, and the hypertension event. The
        // sleep-duration aggregate moved out of the rows into the catalog's derivedAggregates.
        expectedIdentifierList.append(contentsOf: [
            "HKCategoryTypeIdentifierHypertensionEvent",
            "HKCharacteristicTypeIdentifierActivityMoveMode",
            "HKCharacteristicTypeIdentifierBiologicalSex",
            "HKCharacteristicTypeIdentifierBloodType",
            "HKCharacteristicTypeIdentifierDateOfBirth",
            "HKCharacteristicTypeIdentifierFitzpatrickSkinType",
            "HKCharacteristicTypeIdentifierWheelchairUse",
            "HKDataTypeUserAnnotatedMedicationConcept",
            "HKDocumentTypeIdentifierCDA",
            "HKMedicationDoseEventTypeIdentifierMedicationDoseEvent"
        ])
        let expectedIdentifiers = Set(expectedIdentifierList)

        #expect(sourceIdentifiers.count == Set(sourceIdentifiers).count)
        #expect(Set(sourceIdentifiers) == expectedIdentifiers)
        #expect(rows.filter { $0.implementationStatus == .supported }.allSatisfy {
            !$0.measurements.isEmpty
        })
        #expect(rows.filter { $0.implementationStatus == .platformExclusive }.allSatisfy {
            $0.measurements.isEmpty && !$0.title.isEmpty
        })
        #expect(rows.filter {
            $0.implementationStatus == .deferred || $0.implementationStatus == .intentionallyUnsupported
        }
        .allSatisfy { $0.requirement?.isEmpty == false })

        // Supported rows the sample-driven binding table intentionally does not serve: the ECG
        // evidence path, the workout graph deferred to the next round, the characteristic reads
        // that are not HKSamples, and the panel components admitted only inside the correlation.
        let sampleBindingExemptions: Set<String> = [
            HKObjectType.electrocardiogramType().identifier,
            HKWorkoutType.workoutType().identifier,
            HKCharacteristicTypeIdentifier.bloodType.rawValue,
            HKCharacteristicTypeIdentifier.wheelchairUse.rawValue,
            HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
            HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        ]
        for row in rows where row.implementationStatus == .supported {
            let identifier = row.sourceTypeIdentifier
            let binding = HealthKitFHIRCatalog.binding(forSourceTypeIdentifier: identifier)
            if sampleBindingExemptions.contains(identifier) {
                #expect(binding == nil, "\(identifier) is served outside the sample binding table")
            } else {
                #expect(binding != nil, "\(identifier) is supported but has no binding")
                #expect(binding?.contract.id == row.measurements.first?.id)
            }
        }
        for row in rows where row.implementationStatus != .supported {
            #expect(
                HealthKitFHIRCatalog.binding(forSourceTypeIdentifier: row.sourceTypeIdentifier) == nil,
                "\(row.sourceTypeIdentifier) is not supported but has a binding"
            )
        }
    }

    @Test
    func periodMetricsRejectZeroLengthIntervals() {
        let sample = quantitySample(.stepCount, unit: .count(), value: 431, interval: 0)
        #expect(throws: GroveHealthKitFHIRError.invalidEffectivePeriod(
            sampleType: HKQuantityTypeIdentifier.stepCount.rawValue
        )) {
            try converter.convert(sample, context: context)
        }
    }

    @Test
    func subjectReferenceFailsClosedWhenEmptyOrWronglyTyped() {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let emptyContext = HealthKitFHIRConversionContext(
            subject: Reference(),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: GroveHealthKitFHIRError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try converter.convert(sample, context: emptyContext)
        }

        let wrongTypeContext = HealthKitFHIRConversionContext(
            subject: Reference(reference: "Observation/not-a-patient"),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: GroveHealthKitFHIRError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try converter.convert(sample, context: wrongTypeContext)
        }
    }

    @Test(
        "Malformed or ambiguous literal subject references fail closed",
        arguments: [
            "Patient/",
            "Patient/id/",
            "Patient/id/extra",
            "prefix/Patient/id",
            "Observation/id",
            "https://example.org/fhir/Observation/id",
            "https://example.org/fhir/Patient/id/",
            "https://example.org/fhir/Patient/id/extra",
            "https://example.org/fhir/Patient/id/_history/2",
            "https://example.org/fhir/Patient/old/_history/2/Patient/id",
            "https://example.org/fhir/Patient/id?view=full",
            "https://example.org/fhir/Patient/id#section",
            "https://user@example.org/fhir/Patient/id",
            "https://example.org/fhir/Patient/id with-space",
            "file:///fhir/Patient/id"
        ]
    )
    func malformedSubjectLiteralFailsClosed(literal: String) {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let invalidContext = HealthKitFHIRConversionContext(
            subject: Reference(reference: literal.asFHIRStringPrimitive()),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )

        #expect(throws: GroveHealthKitFHIRError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try converter.convert(sample, context: invalidContext)
        }
    }

    @Test(
        "Exact relative and HTTP(S) absolute subject references are preserved",
        arguments: [
            "Patient/example",
            "http://example.org/fhir/Patient/example",
            "https://example.org/base/fhir/Patient/example"
        ]
    )
    func validSubjectLiteralIsPreserved(literal: String) throws {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let validContext = HealthKitFHIRConversionContext(
            subject: Reference(reference: literal.asFHIRStringPrimitive()),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )

        let conversion = try converter.convert(sample, context: validContext)
        #expect(conversion.observation.subject?.reference?.value?.string == literal)
    }

    @Test
    func identifierOnlySubjectRequiresCompleteIdentityAndExactType() throws {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let validReference = Reference(
            identifier: Identifier(
                system: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/fhir/identifiers/patient")),
                value: "patient-1".asFHIRStringPrimitive()
            ),
            type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
        )
        let validContext = HealthKitFHIRConversionContext(
            subject: validReference,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        _ = try converter.convert(sample, context: validContext)

        let missingSystemContext = HealthKitFHIRConversionContext(
            subject: Reference(
                identifier: Identifier(value: "patient-1".asFHIRStringPrimitive()),
                type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
            ),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: GroveHealthKitFHIRError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try converter.convert(sample, context: missingSystemContext)
        }

        let missingTypeContext = HealthKitFHIRConversionContext(
            subject: Reference(identifier: validReference.identifier),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: GroveHealthKitFHIRError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try converter.convert(sample, context: missingTypeContext)
        }

        let ambiguousContext = HealthKitFHIRConversionContext(
            subject: Reference(
                identifier: validReference.identifier,
                reference: "Patient/patient-1",
                type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
            ),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: GroveHealthKitFHIRError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try converter.convert(sample, context: ambiguousContext)
        }
    }

    @Test
    func duplicateResearchStudyReferencesFailClosed() {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let duplicateContext = HealthKitFHIRConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant,
            researchStudies: [
                Reference(reference: "ResearchStudy/study-1"),
                Reference(reference: "ResearchStudy/study-1")
            ]
        )

        #expect(throws: GroveHealthKitFHIRError.duplicateReference(field: "researchStudies")) {
            try converter.convert(sample, context: duplicateContext)
        }
    }

    @Test
    func batchReportsEveryFailureWithoutDroppingRecords() {
        let supported = quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4)
        let deferred = HKCorrelation(
            type: HKCorrelationType(.food),
            start: timestamp,
            end: timestamp,
            objects: [quantitySample(.dietaryEnergyConsumed, unit: .kilocalorie(), value: 320)]
        )
        let result = converter.convert([supported, deferred], context: context)
        #expect(result.conversions.count == 1)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.sourceUUID == deferred.uuid)
        #expect(result.failures.first?.reason == .unsupportedSampleType(deferred.sampleType.identifier))
    }
}


extension Observation.EffectiveX {
    fileprivate var isPeriod: Bool {
        if case .period = self {
            return true
        }
        return false
    }
}

#endif
