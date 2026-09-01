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
            case .activeEnergy: .init(shared: MeasurementCatalog.activeEnergy)
            case .basalBodyTemperature: .init(shared: MeasurementCatalog.basalBodyTemperature)
            case .bodyFatPercentage: .init(shared: MeasurementCatalog.bodyFatPercentage)
            case .bodyHeight: .init(shared: MeasurementCatalog.bodyHeight)
            case .bodyMassIndex: .bodyMassIndex
            case .bodyTemperature: .init(shared: MeasurementCatalog.bodyTemperature)
            case .bodyWeight: .init(shared: MeasurementCatalog.bodyWeight)
            case .dietaryEnergy: .init(shared: MeasurementCatalog.dietaryEnergy)
            case .distanceCrossCountrySkiing, .distanceCycling, .distanceDownhillSnowSports,
                 .distancePaddleSports, .distanceRowing, .distanceSkatingSports,
                 .distanceSwimming, .distanceWalkingRunning, .distanceWheelchair:
                .init(shared: MeasurementCatalog.distance)
            case .heartRate: .init(shared: MeasurementCatalog.heartRate)
            case .heartRateVariabilitySDNN: .init(shared: MeasurementCatalog.heartRateVariabilitySdnn)
            case .oxygenSaturation: .init(shared: MeasurementCatalog.oxygenSaturation)
            case .respiratoryRate: .init(shared: MeasurementCatalog.respiratoryRate)
            case .stepCount: .init(shared: MeasurementCatalog.stepCount)
            case .vo2Max: .init(shared: MeasurementCatalog.vo2Max)
            case .walkingSpeed: .init(shared: HealthKitMeasurementCatalog.walkingSpeed)
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

    private let converter = HealthKitConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private var context: HealthKitConversionContext {
        HealthKitConversionContext(
            subject: .testPatient,
            converter: HealthKitApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
    }

    @Test("A valid sync pair is writer-scoped and omitted when its writer is unavailable")
    func syncIdentityIsCarried() throws {
        let converter = HealthKitConverter()

        let plain = try converter.convert(
            quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4),
            context: context
        )
        let plainIdentifiers = try #require(plain.observation.identifier).map(BusinessIdentifier.init)
        #expect(plainIdentifiers.map(\.role) == [.sourceRecord, .sourceOutput])
        #expect(plain.observation.extension?.contains { $0.url == Canonicals.writerRecordVersion } != true)

        // The same logical measurement, saved twice: HealthKit replaces the first and the
        // replacement carries a new object UUID, so only the sync identity ties them together.
        let first = try converter.convert(
            quantitySample(
                .bodyMass,
                unit: .gramUnit(with: .kilo),
                value: 68.4,
                metadata: [HKMetadataKeySyncIdentifier: "scale-2026-08-19", HKMetadataKeySyncVersion: 1]
            ),
            context: context
        )
        let revision = try converter.convert(
            quantitySample(
                .bodyMass,
                unit: .gramUnit(with: .kilo),
                value: 68.9,
                metadata: [HKMetadataKeySyncIdentifier: "scale-2026-08-19", HKMetadataKeySyncVersion: 2]
            ),
            context: context
        )

        func syncIdentifier(_ conversion: HealthKitConversion) -> String? {
            conversion.observation.identifier?
                .first { (try? BusinessIdentifier($0).role) == .writerRecord }?
                .value?.value?.string
        }
        // Canonical decimal text, not an integer: a sync version is an NSNumber and a Health
        // Connect client record version is a Long, neither of which fits FHIR's 32-bit integer.
        func syncVersion(_ conversion: HealthKitConversion) -> String? {
            guard case .string(let value) = conversion.observation.extension?
                .first(where: { $0.url == Canonicals.writerRecordVersion })?.value else {
                return nil
            }
            return value.value?.string
        }

        // These public sample factories have no attributable source, so the valid pair is omitted
        // rather than scoped to an empty writer.
        #expect(syncIdentifier(first) == nil)
        #expect(syncVersion(first) == nil)
        #expect(syncIdentifier(revision) == nil)
        #expect(syncVersion(revision) == nil)
        // The object identifiers differ, which is exactly why the sync identity is needed.
        #expect(first.observation.identifier?.first != revision.observation.identifier?.first)

        // Exercise the production mapper through its source-attribution seam. HealthKit's public
        // sample factory does not let a unit test construct the HKSourceRevision that owns it.
        var attributable = plain.observation
        try HealthKitConverter.applySyncIdentity(
            metadata: [
                HKMetadataKeySyncIdentifier: "scale-2026-08-19",
                HKMetadataKeySyncVersion: NSNumber(value: UInt64.max)
            ],
            writerApplication: "org.example.connected-scale",
            to: &attributable,
            context: context
        )
        let attributableConversion = HealthKitConversion(
            localSourceUUID: plain.localSourceUUID,
            localSourceTypeIdentifier: plain.localSourceTypeIdentifier,
            subjectIdentity: plain.subjectIdentity,
            repositoryScope: plain.repositoryScope,
            sourceIdentifier: plain.sourceIdentifier,
            graphIdentifiers: plain.graphIdentifiers,
            observation: attributable,
            recordingDevice: plain.recordingDevice,
            converterApplication: plain.converterApplication,
            converterHost: plain.converterHost,
            sourceAuthor: plain.sourceAuthor,
            sourceAuthorHost: plain.sourceAuthorHost,
            provenance: plain.provenance,
            graph: plain.graph
        )
        #expect(syncIdentifier(attributableConversion) != nil)
        #expect(syncVersion(attributableConversion) == "18446744073709551615")
    }

    @Test("HealthKit sync identifier and version are a strict nonnegative-integral pair")
    func syncIdentityRejectsMalformedPairs() throws {
        let plain = try converter.convert(
            quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4),
            context: context
        )
        let invalidIdentifier = HealthKitConversionError.invalidMetadataValue(
            key: HKMetadataKeySyncIdentifier
        )
        let invalidVersion = HealthKitConversionError.invalidMetadataValue(
            key: HKMetadataKeySyncVersion
        )

        #expect(throws: invalidVersion) {
            var observation = plain.observation
            try HealthKitConverter.applySyncIdentity(
                metadata: [HKMetadataKeySyncIdentifier: "logical-record"],
                writerApplication: "org.example.writer",
                to: &observation,
                context: context
            )
        }
        #expect(throws: invalidIdentifier) {
            var observation = plain.observation
            try HealthKitConverter.applySyncIdentity(
                metadata: [HKMetadataKeySyncVersion: 1],
                writerApplication: "org.example.writer",
                to: &observation,
                context: context
            )
        }

        for invalid in [true, -1, 1.5, "1", NSNumber(value: Double.nan)] as [Any] {
            #expect(throws: invalidVersion) {
                var observation = plain.observation
                try HealthKitConverter.applySyncIdentity(
                    metadata: [
                        HKMetadataKeySyncIdentifier: "logical-record",
                        HKMetadataKeySyncVersion: invalid
                    ],
                    writerApplication: "org.example.writer",
                    to: &observation,
                    context: context
                )
            }
        }
        for invalid in ["", 1] as [Any] {
            #expect(throws: invalidIdentifier) {
                var observation = plain.observation
                try HealthKitConverter.applySyncIdentity(
                    metadata: [
                        HKMetadataKeySyncIdentifier: invalid,
                        HKMetadataKeySyncVersion: 1
                    ],
                    writerApplication: "org.example.writer",
                    to: &observation,
                    context: context
                )
            }
        }
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

    /// The full-catalog matrix proves the profile, code, and lineage facts for every row; this
    /// hand-picked set exists for the source units it converts from and its exact decimal scaling.
    @Test("Every source unit normalizes to its contract unit and exact decimal", arguments: QuantityCase.allCases)
    func normalizesSourceUnits(testCase: QuantityCase) throws {
        let sample = quantitySample(
            testCase.identifier,
            unit: testCase.sourceUnit,
            value: testCase.sourceValue
        )
        let conversion = try converter.convert(sample, context: context)
        let quantity: Quantity = try #require({
            guard case .quantity(let quantity) = conversion.observation.value else {
                return nil
            }
            return quantity
        }())

        let profileClaims = try #require(conversion.observation.meta?.profile)
        #expect(profileClaims == testCase.contract.profiles)
        if profileClaims.count == 1 {
            #expect(ProfileClaims.singleObservationProfiles.contains(profileClaims[0]))
        } else {
            #expect(profileClaims.count == ProfileClaims.observationAdapterCardinality)
            #expect(profileClaims.contains(Profile.healthkitObservation))
        }
        if testCase != .bodyMassIndex {
            #expect(profileClaims.allSatisfy { !ProfileClaims.forbiddenExplicitProfiles.contains($0) })
        }
        #expect(quantity.system?.value?.url.absoluteString == testCase.contract.quantity?.system)
        #expect(quantity.code?.value?.string == testCase.contract.quantity?.code)
        #expect(conversion.observation.effective?.isPeriod == (testCase.contract.effective == .period))
        if testCase == .heartRate {
            #expect(testCase.contract.effective == .dateTimeOrPeriod)
            guard case .dateTime = conversion.observation.effective else {
                Issue.record("A normal HealthKit heart-rate sample must use effectiveDateTime")
                return
            }
        }
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
            Profile.groveMobileSleepStage,
            Profile.healthkitObservation
        ])
        #expect(codings.count == 2)
        #expect(codings[0].system?.value?.url.absoluteString == Canonicals.sleepStageCodeSystem.value?.url.absoluteString)
        #expect(codings[0].code?.value?.string == testCase.expectedCode)
        #expect(codings[1].system == Canonicals.healthKitSleepAnalysis)
        #expect(codings[1].code?.value?.string == testCase.expectedSourceCode)
        #expect(MeasurementCatalog.sleepStage.allowedValues.contains(testCase.expectedCode))
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
            Profile.groveMobileBloodPressure,
            Profile.healthkitObservation
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
        attributedContext = HealthKitConversionContext(
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
        #expect(try BusinessIdentifier(first.sourceIdentifier) == first.graphIdentifiers.sourceRecord)
        #expect(first.graphIdentifiers.sourceRecord.role == .sourceRecord)
        #expect(first.bundle.meta?.profile == [Profile.groveMobileExchangeBundle])
        #expect(first.provenance.meta?.profile == [
            HealthKitContract.conversionProvenanceProfile
        ])
        #expect(first.bundle.identifier == first.graphIdentifiers.event.fhirIdentifier)
        #expect(entries.compactMap(\.fullUrl) == second.bundle.entry?.compactMap(\.fullUrl))
        #expect(entries.count >= 5)
        #expect(entries.allSatisfy { entry in
            let identityExtensions = entry.extension?.filter {
                $0.url == Canonicals.entryNodeKey
            }
            return entry.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true
                && identityExtensions?.count == 1
        })

        let fullURLs = Set(entries.compactMap { $0.fullUrl?.value?.url.absoluteString })
        let targetReference = first.provenance.target.first?.reference?.value?.string
        let assemblerReference = first.provenance.agent.first?.who.reference?.value?.string
        let sourceEntities = try #require(first.provenance.entity)
        let sourceEntity = try #require(sourceEntities.first)
        let observationURL = try ExchangeIdentity.fullURL(for: first.graphIdentifiers.primaryOutput)
        #expect(first.observation.device.flatMap { $0.reference?.value?.string }.map(fullURLs.contains) == true)
        #expect(targetReference == observationURL)
        #expect(assemblerReference.map(fullURLs.contains) == true)
        #expect(sourceEntities.count == 1)
        #expect(sourceEntity.role == FHIRPrimitive(.source))
        #expect(sourceEntity.what.reference == nil)
        #expect(sourceEntity.what.identifier == first.sourceIdentifier)
        let recordingIdentifiers = try #require(first.recordingDevice?.identifier).map(BusinessIdentifier.init)
        #expect(recordingIdentifiers.map(\.role) == [.deviceSnapshot, .recordingDevice])
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
        let explicitContext = HealthKitConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: timestamp,
            recordingDeviceStableUnitToken: "test-recording-device",
            repositoryIDs: HealthKitRepositoryIDs(
                bundle: try RepositoryID("bundle-1"),
                observation: try RepositoryID("observation-1"),
                recordingDevice: try RepositoryID("device-1"),
                converterApplication: try RepositoryID("application-1"),
                provenance: try RepositoryID("provenance-1")
            )
        )
        let conversion = try converter.convert(sample, context: explicitContext)

        #expect(conversion.bundle.id?.value?.string == "bundle-1")
        #expect(conversion.observation.id?.value?.string == "observation-1")
        #expect(conversion.recordingDevice?.id?.value?.string == "device-1")
        #expect(conversion.converterApplication.id?.value?.string == "application-1")
        #expect(conversion.provenance.id?.value?.string == "provenance-1")
        let identifiers = try #require(conversion.recordingDevice?.identifier).map(BusinessIdentifier.init)
        #expect(identifiers.map(\.role) == [.deviceSnapshot, .recordingDevice])
        #expect(identifiers.allSatisfy { $0.value.hasPrefix("v0:test:1:") })
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
        let authorizedContext = HealthKitConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: timestamp,
            udiDisclosurePolicy: .authorizedUDI
        )
        let conversion = try converter.convert(sample, context: authorizedContext)

        let identifiers = try #require(conversion.recordingDevice?.identifier).map(BusinessIdentifier.init)
        #expect(identifiers.map(\.role) == [.deviceSnapshot, .recordingDevice])
        #expect(conversion.recordingDevice?.udiCarrier?.first?.deviceIdentifier?.value?.string == "authorized-udi")
    }

    @Test
    func typedMetadataDoesNotInferUnknownFacts() throws {
        let automatic = try converter.convert(
            quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4),
            context: context
        )
        #expect(automatic.observation.extension?.contains {
            $0.url == Canonicals.recordingMethod
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
            $0.url == Canonicals.recordingMethod
        } == true)
        #expect(manual.observation.performer == nil)
    }

    @Test
    func unmodelledMetadataAndExternalUUIDAreNotInventedAsFHIRComponents() throws {
        let conversion = try converter.convert(
            quantitySample(
                .heartRate,
                unit: .count().unitDivided(by: .minute()),
                value: 72,
                metadata: [
                    "ThirdPartyAppNote": "a key no contract models",
                    HKMetadataKeyExternalUUID: "linkable-and-withheld"
                ]
            ),
            context: context
        )
        // The IG's metadata mapping is closed. An open source dictionary cannot silently create
        // unprofiled Observation components, and ExternalUUID needs its own governed mapping rather
        // than inheriting the policy for HKObject.uuid.
        #expect(conversion.observation.component?.contains {
            $0.code.text?.value?.string == "ThirdPartyAppNote"
                || $0.code.text?.value?.string == HKMetadataKeyExternalUUID
        } != true)
        let encoded = String(decoding: try JSONEncoder().encode(conversion.bundle), as: UTF8.self)
        #expect(!encoded.contains("a key no contract models"))
        #expect(!encoded.contains("linkable-and-withheld"))
    }

    @Test
    func nativeHealthKitUUIDDisclosureIsExplicitTypedAndPrimaryOnly() throws {
        let sample = quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4)
        let nativeSystem = IdentifierSystem("https://study.example/fhir/identifier/healthkit-object")
        let nativeType = try HealthKitNativeIdentifierType(
            system: IdentifierSystem("https://study.example/fhir/CodeSystem/native-identifier-type"),
            code: "healthkit-object-uuid",
            display: "HealthKit object UUID"
        )

        let omitted = try converter.convert(sample, context: context)
        #expect(omitted.observation.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        } != true)

        let disclosed = try converter.convert(
            sample,
            context: HealthKitConversionContext(
                subject: .testPatient,
                converter: HealthKitApplication(
                    name: "Example Study",
                    bundleIdentifier: "org.grovealliance.example-study",
                    version: "2.0.0 (42)"
                ),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
                conversionInstant: timestamp,
                nativeIdentifierDisclosurePolicy: .authorized(system: nativeSystem, type: nativeType)
            )
        )
        let native = try #require(disclosed.observation.identifier?.first {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        })
        #expect(native.value?.value?.string == sample.uuid.uuidString.lowercased())
        #expect(native.type?.coding?.first?.system?.value?.url.absoluteString == nativeType.system.rawValue)
        #expect(native.type?.coding?.first?.code?.value?.string == nativeType.code)
        #expect(disclosed.observation.id == nil)
        #expect(disclosed.provenance.entity?.contains {
            $0.what.identifier?.system?.value?.url.absoluteString == nativeSystem.rawValue
        } == false)
        let bundleJSON = String(decoding: try JSONEncoder().encode(disclosed.bundle), as: UTF8.self)
        #expect(bundleJSON.components(separatedBy: sample.uuid.uuidString.lowercased()).count == 2)
    }

    @Test
    func nativeIdentifierTypeCannotMasqueradeAsGroveGraphRole() throws {
        #expect(throws: HealthKitNativeIdentifierType.ConfigurationError.groveGraphRoleSystem) {
            try HealthKitNativeIdentifierType(
                system: IdentifierSystem(try #require(
                    Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
                )),
                code: GroveIdentifierRole.sourceRecord.rawValue
            )
        }
    }

    @Test("Governed native Identifier.type enforces the R4 code lexical form")
    func nativeIdentifierTypeRejectsMalformedCodeAndBlankDisplay() throws {
        let system: IdentifierSystem =
            "https://study.example/fhir/CodeSystem/native-identifier-type"
        for invalid in [" source-id", "source-id ", "source  id", "source\tid", "source\nid", "source\u{0000}id"] {
            #expect(throws: GovernedSourceIdentifierType.ConfigurationError.invalidCodeLexicalForm) {
                try GovernedSourceIdentifierType(system: system, code: invalid)
            }
        }
        #expect(throws: GovernedSourceIdentifierType.ConfigurationError.emptyCode) {
            try GovernedSourceIdentifierType(system: system, code: "")
        }
        #expect(throws: GovernedSourceIdentifierType.ConfigurationError.blankDisplay) {
            try GovernedSourceIdentifierType(system: system, code: "source-id", display: " \n ")
        }
    }

    @Test("Native identifiers cannot reuse generic or provider opaque namespaces")
    func nativeIdentifierSystemCannotReuseOpaqueGraphNamespace() throws {
        let graphRoot: IdentifierSystem = "https://study.example.org/fhir/identifiers/native-collision"
        let identitySystems = HealthKitConversionContext(
            subject: .testPatient,
            converter: HealthKitApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: graphRoot,
            conversionInstant: timestamp
        ).identityScope.systems
        for collidingNativeSystem in [
            identitySystems.sourceRecord,
            identitySystems.providerOutput,
            identitySystems.providerArtifact
        ] {
            let disclosureContext = HealthKitConversionContext(
                subject: .testPatient,
                converter: HealthKitApplication(
                    name: "Example Study",
                    bundleIdentifier: "org.grovealliance.example-study",
                    version: "2.0.0 (42)"
                ),
                graphIdentifierSystem: graphRoot,
                conversionInstant: timestamp,
                nativeIdentifierDisclosurePolicy: .authorized(system: collidingNativeSystem)
            )
            #expect(throws: HealthKitConversionError.invalidExchangeIdentity(
                "native HealthKit identifier system must not reuse a Grove graph identity system"
            )) {
                try converter.convert(
                    quantitySample(.bodyMass, unit: .gramUnit(with: .kilo), value: 68.4),
                    context: disclosureContext
                )
            }
        }
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
        #expect(throws: HealthKitConversionError.unsupportedMetadataValue(
            key: HKMetadataKeyHeartRateMotionContext,
            value: "99"
        )) {
            try converter.convert(invalid, context: context)
        }
    }

    @Test
    func healthKitTimeZoneMetadataIsTypedAndFailClosed() throws {
        let missing = try HealthKitConverter.healthKitTimeZone(metadata: [:])
        #expect(missing.secondsFromGMT(for: timestamp) == 0)

        let identifier = "America/Los_Angeles"
        let explicit = try HealthKitConverter.healthKitTimeZone(metadata: [HKMetadataKeyTimeZone: identifier])
        #expect(explicit.identifier == identifier)

        #expect(throws: HealthKitConversionError.unsupportedMetadataValue(
            key: HKMetadataKeyTimeZone,
            value: "Not/A-Time-Zone"
        )) {
            try HealthKitConverter.healthKitTimeZone(metadata: [HKMetadataKeyTimeZone: "Not/A-Time-Zone"])
        }
        #expect(throws: HealthKitConversionError.unsupportedMetadataValue(
            key: HKMetadataKeyTimeZone,
            value: "42"
        )) {
            try HealthKitConverter.healthKitTimeZone(metadata: [HKMetadataKeyTimeZone: 42])
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
            Profile.groveMobileBloodGlucoseUnspecifiedSpecimen,
            Profile.healthkitObservation
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

    #if !os(watchOS)
    @Test("Clinical transport preserves exact DSTU2 and R4 bytes with their declared release")
    @available(iOS 18, macOS 15, *)
    func clinicalTransportPreservesAdmittedReleases() throws {
        let sourceUUID = try #require(UUID(uuidString: "be22dfdc-8870-4413-9f8f-8c2aad0c9cbc"))
        let dstu2JSON = Data("  {\"resourceType\":\"Observation\",\"id\":\"dstu2\"}\n".utf8)
        let r4JSON = Data("{\n  \"resourceType\": \"Observation\", \"id\": \"r4\"\n}\n".utf8)

        let dstu2 = try HealthKitConverter.clinicalRecordingEvidence(
            data: dstu2JSON,
            release: .dstu2,
            versionDescription: "1.0.2",
            sourceUUID: sourceUUID,
            sourceTypeIdentifier: "HKClinicalTypeIdentifierLabResultRecord"
        )
        let r4Evidence = try HealthKitConverter.clinicalRecordingEvidence(
            data: r4JSON,
            release: .r4,
            versionDescription: "4.0.1",
            sourceUUID: sourceUUID,
            sourceTypeIdentifier: "HKClinicalTypeIdentifierLabResultRecord"
        )

        #expect(dstu2.payload == dstu2JSON)
        #expect(dstu2.format.rawValue == HealthKitContract.clinicalFHIRPayloadFormatCode)
        #expect(dstu2.clinicalFHIRReleaseCode == "dstu2")
        #expect(r4Evidence.payload == r4JSON)
        #expect(r4Evidence.format.rawValue == HealthKitContract.clinicalFHIRPayloadFormatCode)
        #expect(r4Evidence.clinicalFHIRReleaseCode == "r4")
    }

    @Test("Unknown clinical releases fail before Grove creates an exchange document")
    @available(iOS 18, macOS 15, *)
    func unknownClinicalReleaseFailsClosed() throws {
        let sourceUUID = try #require(UUID(uuidString: "be22dfdc-8870-4413-9f8f-8c2aad0c9cbc"))
        let payload = Data(#"{"resourceType":"Observation"}"#.utf8)

        #expect(throws: HealthKitConversionError.unsupportedClinicalRelease("unknown")) {
            _ = try HealthKitConverter.clinicalRecordingEvidence(
                data: payload,
                release: .unknown,
                versionDescription: "unknown",
                sourceUUID: sourceUUID,
                sourceTypeIdentifier: "HKClinicalTypeIdentifierLabResultRecord"
            )
        }
    }

    @Test(
        "Clinical transport rejects payload syntax that the implementation guides do not admit",
        arguments: [
            Data(#"{"resourceType":"Observation","resourceType":"Patient"}"#.utf8),
            Data(#"{"resourceType":"observation"}"#.utf8),
            Data([0xEF, 0xBB, 0xBF]) + Data(#"{"resourceType":"Observation"}"#.utf8)
        ]
    )
    @available(iOS 18, macOS 15, *)
    func invalidClinicalResourceSyntaxFailsClosed(payload: Data) throws {
        let sourceUUID = try #require(UUID(uuidString: "be22dfdc-8870-4413-9f8f-8c2aad0c9cbc"))

        #expect(throws: HealthKitConversionError.undecodableClinicalRecord(sourceUUID)) {
            _ = try HealthKitConverter.clinicalRecordingEvidence(
                data: payload,
                release: .r4,
                versionDescription: "4.0.1",
                sourceUUID: sourceUUID,
                sourceTypeIdentifier: "HKClinicalTypeIdentifierLabResultRecord"
            )
        }
    }

    @Test("Typed R4 inspection still rejects a DSTU2 payload without changing transport support")
    @available(iOS 18, macOS 15, *)
    func typedR4InspectionRejectsDSTU2() throws {
        let sourceUUID = try #require(UUID(uuidString: "be22dfdc-8870-4413-9f8f-8c2aad0c9cbc"))
        let dstu2JSON = Data(#"{"resourceType":"Observation","id":"dstu2"}"#.utf8)

        #expect(throws: HealthKitConversionError.unsupportedClinicalRelease("1.0.2")) {
            _ = try HealthKitConverter.decodeR4ClinicalResource(
                data: dstu2JSON,
                release: .dstu2,
                versionDescription: "1.0.2",
                sourceUUID: sourceUUID
            )
        }
    }
    #endif

    @Test
    func catalogIsACompleteUniqueMatrixForKnownHealthKitTypes() {
        let rows = HealthKitCatalog.entries
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
        #expect(rows.filter { $0.implementationStatus == .intentionallyUnsupported }
        .allSatisfy { $0.requirement?.isEmpty == false })

        // Supported rows the sample-driven binding table intentionally does not serve: the ECG
        // evidence path, the characteristic reads that are not HKSamples, and the panel components
        // admitted only inside the correlation. Workouts are served now, so they are not exempt.
        let sampleBindingExemptions: Set<String> = [
            HKObjectType.electrocardiogramType().identifier,
            HKDataTypeIdentifierHeartbeatSeries,
            HKWorkoutRouteTypeIdentifier,
            HKDocumentTypeIdentifier.CDA.rawValue,
            HKClinicalTypeIdentifier.allergyRecord.rawValue,
            HKClinicalTypeIdentifier.conditionRecord.rawValue,
            HKClinicalTypeIdentifier.immunizationRecord.rawValue,
            HKClinicalTypeIdentifier.labResultRecord.rawValue,
            HKClinicalTypeIdentifier.medicationRecord.rawValue,
            HKClinicalTypeIdentifier.procedureRecord.rawValue,
            HKClinicalTypeIdentifier.vitalSignRecord.rawValue,
            "HKCharacteristicTypeIdentifierBiologicalSex",
            "HKCharacteristicTypeIdentifierDateOfBirth",
            "HKCharacteristicTypeIdentifierFitzpatrickSkinType",
            "HKCorrelationTypeIdentifierFood",
            "HKDataTypeIdentifierAudiogram",
            HKCharacteristicTypeIdentifier.bloodType.rawValue,
            HKCharacteristicTypeIdentifier.wheelchairUse.rawValue,
            HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
            HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        ]
        for row in rows where row.implementationStatus == .supported {
            let identifier = row.sourceTypeIdentifier
            let binding = HealthKitCatalog.binding(forSourceTypeIdentifier: identifier)
            if sampleBindingExemptions.contains(identifier) {
                #expect(binding == nil, "\(identifier) is served outside the sample binding table")
            } else {
                #expect(binding != nil, "\(identifier) is supported but has no binding")
                #expect(binding?.contract.id == row.measurements.first?.id)
            }
        }
        for row in rows where row.implementationStatus != .supported {
            #expect(
                HealthKitCatalog.binding(forSourceTypeIdentifier: row.sourceTypeIdentifier) == nil,
                "\(row.sourceTypeIdentifier) is not supported but has a binding"
            )
        }
    }

    @Test
    func periodMetricsRejectZeroLengthIntervals() {
        let sample = quantitySample(.stepCount, unit: .count(), value: 431, interval: 0)
        #expect(throws: HealthKitConversionError.invalidEffectivePeriod(
            sampleType: HKQuantityTypeIdentifier.stepCount.rawValue
        )) {
            try converter.convert(sample, context: context)
        }
    }

    @Test("Generated quantity domains reject invalid values and retain inclusive zero")
    func generatedQuantityDomainsAreEnforced() throws {
        let steps = try #require(MeasurementCatalog.stepCount.quantity)
        let percentage = try #require(MeasurementCatalog.oxygenSaturation.quantity)
        let valence = try #require(HealthKitMeasurementCatalog.stateOfMind.quantity)

        let zero = try HealthKitConverter.fhirQuantity(value: 0, contract: steps)
        #expect(zero.value?.value?.decimal == 0)
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitConverter.fhirQuantity(value: 1.5, contract: steps)
        }
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitConverter.fhirQuantity(value: -1, contract: steps)
        }
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitConverter.fhirQuantity(value: 100.01, contract: percentage)
        }
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitConverter.fhirQuantity(value: -0.01, contract: percentage)
        }
        #expect(throws: Never.self) {
            try HealthKitConverter.fhirQuantity(value: 100, contract: percentage)
        }
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitConverter.fhirQuantity(value: 1.01, contract: valence)
        }
        #expect(throws: Never.self) {
            try HealthKitConverter.fhirQuantity(value: -1, contract: valence)
        }
    }

    @Test
    func subjectReferenceFailsClosedWhenEmptyOrWronglyTyped() {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let emptyContext = HealthKitConversionContext(
            subject: Reference(),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: HealthKitConversionError.invalidReference(
            field: "subject",
            expectedResourceType: .patient
        )) {
            try converter.convert(sample, context: emptyContext)
        }

        let wrongTypeContext = HealthKitConversionContext(
            subject: .testLogicalReference(resourceType: .observation, value: "not-a-patient"),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: HealthKitConversionError.invalidReference(
            field: "subject",
            expectedResourceType: .patient
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
        let invalidContext = HealthKitConversionContext(
            subject: Reference(reference: literal.asFHIRStringPrimitive()),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )

        #expect(throws: HealthKitConversionError.invalidExchangeIdentity(
            "subject must use an identifier-only logical Reference; literals require a Bundle entry"
        )) {
            try converter.convert(sample, context: invalidContext)
        }
    }

    @Test(
        "Even syntactically valid literals fail when their target is absent from the Bundle",
        arguments: [
            "Patient/example",
            "http://example.org/fhir/Patient/example",
            "https://example.org/base/fhir/Patient/example"
        ]
    )
    func unboundSubjectLiteralFailsClosed(literal: String) {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let validContext = HealthKitConversionContext(
            subject: Reference(reference: literal.asFHIRStringPrimitive()),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )

        #expect(throws: HealthKitConversionError.invalidExchangeIdentity(
            "subject must use an identifier-only logical Reference; literals require a Bundle entry"
        )) {
            try converter.convert(sample, context: validContext)
        }
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
        let validContext = HealthKitConversionContext(
            subject: validReference,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        _ = try converter.convert(sample, context: validContext)

        let missingSystemContext = HealthKitConversionContext(
            subject: Reference(
                identifier: Identifier(value: "patient-1".asFHIRStringPrimitive()),
                type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
            ),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: HealthKitConversionError.invalidReference(
            field: "subject",
            expectedResourceType: .patient
        )) {
            try converter.convert(sample, context: missingSystemContext)
        }

        let missingTypeContext = HealthKitConversionContext(
            subject: Reference(identifier: validReference.identifier),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: HealthKitConversionError.invalidReference(
            field: "subject",
            expectedResourceType: .patient
        )) {
            try converter.convert(sample, context: missingTypeContext)
        }

        let ambiguousContext = HealthKitConversionContext(
            subject: Reference(
                identifier: validReference.identifier,
                reference: "Patient/patient-1",
                type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
            ),
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant
        )
        #expect(throws: HealthKitConversionError.invalidReference(
            field: "subject",
            expectedResourceType: .patient
        )) {
            try converter.convert(sample, context: ambiguousContext)
        }
    }

    @Test
    func duplicateResearchStudyReferencesFailClosed() {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let duplicateContext = HealthKitConversionContext(
            subject: context.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: context.conversionInstant,
            researchStudies: [
                .testResearchStudy("study-1"),
                .testResearchStudy("study-1")
            ]
        )

        #expect(throws: HealthKitConversionError.duplicateReference(field: "researchStudies")) {
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
        let result = converter.convert([supported, deferred]) { _ in context }
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
