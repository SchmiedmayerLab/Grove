//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// Proves the stored-sample trick still works on this HealthKit, and fails rather than skips when it stops working:
/// every golden rests on the chosen UUID and writer actually reaching the converter.
@Suite
struct StoredSampleFixturesTests {
    private static let uuid = GoldenFixtures.uuid(0xF0)
    private static let writer = GoldenFixtures.foreignWriter

    private static func expectStored(_ sample: HKSample, uuid: UUID = uuid, sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(sample.uuid == uuid, sourceLocation: sourceLocation)
        let revision = sample.sourceRevision
        #expect(revision.source.name == writer.name, sourceLocation: sourceLocation)
        #expect(revision.source.bundleIdentifier == writer.bundleIdentifier, sourceLocation: sourceLocation)
        #expect(revision.version == writer.version, sourceLocation: sourceLocation)
        #expect(revision.productType == writer.productType, sourceLocation: sourceLocation)
        #expect(revision.operatingSystemVersion.majorVersion == 26, sourceLocation: sourceLocation)
        #expect(revision.operatingSystemVersion.minorVersion == 1, sourceLocation: sourceLocation)
        #expect(revision.operatingSystemVersion.patchVersion == 0, sourceLocation: sourceLocation)
    }

    private static func archived<Sample: HKSample>(_ sample: HKSample, as type: Sample.Type) throws -> Sample {
        let data = try NSKeyedArchiver.archivedData(withRootObject: sample, requiringSecureCoding: true)
        let restored = try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
        return try #require(restored)
    }

    @Test("HealthKit still has the private storage the fixtures write")
    func privateStorageIsPresent() {
        #expect(StoredSampleFixtures.privateStorageIsPresent())
    }

    @Test("A key the key table does not declare for a class is refused before anything is written")
    func undeclaredKeysAreRefused() throws {
        let sample = try GoldenFixtures.heartRate(uuid: Self.uuid)
        #expect(throws: StoredSampleFixtures.FixtureError.self) {
            try StoredSampleFixtures.restate(sample, with: ["value": NSNumber(value: 1)])
        }
        #expect(throws: StoredSampleFixtures.FixtureError.self) {
            try StoredSampleFixtures.read("freezeState", of: sample)
        }
        #expect(sample.quantity.doubleValue(for: GoldenFixtures.beatsPerMinute) == 72)
    }

    @Test("A restated sample states facts HealthKit refuses at creation: a reversed interval, mistyped metadata, a far-future instant")
    func restatedSamplesStateRefusedFacts() throws {
        var facts = GoldenCase.seriesFacts(uuid: 0xF1, duration: 30)
        facts.end = facts.start.addingTimeInterval(-30)
        facts.metadata = [HKMetadataKeyTimeZone: 42, HKMetadataKeyWasUserEntered: "yes"]
        let reversed = try StoredSampleFixtures.restated(try GoldenFixtures.heartRate(uuid: Self.uuid), facts: facts)
        #expect(reversed.uuid == GoldenFixtures.uuid(0xF1))
        #expect(reversed.endDate < reversed.startDate)
        #expect(reversed.metadata?[HKMetadataKeyTimeZone] as? Int == 42)
        #expect(reversed.metadata?[HKMetadataKeyWasUserEntered] as? String == "yes")
        try Self.expectStored(reversed, uuid: GoldenFixtures.uuid(0xF1))
        facts.start = Date(timeIntervalSince1970: 253_402_300_800)
        facts.end = facts.start
        let farFuture = try StoredSampleFixtures.restated(try GoldenFixtures.heartRate(uuid: Self.uuid), facts: facts)
        #expect(farFuture.startDate.timeIntervalSince1970 == 253_402_300_800)
    }

    @Test("A stored ECG states its whole reading, and its voltages state their offsets and leads")
    func electrocardiogramsStateTheirReading() throws {
        let reading = StoredElectrocardiogram.Reading(
            classification: try #require(HKElectrocardiogram.Classification(rawValue: 99)),
            symptomsStatus: .present,
            numberOfVoltageMeasurements: 3,
            averageHeartRate: HKQuantity(unit: GoldenFixtures.beatsPerMinute, doubleValue: 72.5),
            samplingFrequency: nil
        )
        let ecg = try StoredSampleFixtures.electrocardiogram(facts: GoldenCase.seriesFacts(uuid: 0xF2, duration: 30), reading: reading)
        #expect(ecg.classification.rawValue == 99)
        #expect(ecg.symptomsStatus == .present)
        #expect(ecg.numberOfVoltageMeasurements == 3)
        #expect(ecg.averageHeartRate?.doubleValue(for: GoldenFixtures.beatsPerMinute) == 72.5)
        #expect(ecg.samplingFrequency == nil)
        try Self.expectStored(ecg, uuid: GoldenFixtures.uuid(0xF2))
        #expect(HealthKitSourceType(ecg) == .electrocardiogram)

        let voltage = try StoredSampleFixtures.voltageMeasurement(offset: 0.252, millivolts: -0.125)
        #expect(voltage.timeSinceSampleStart == 0.252)
        #expect(voltage.quantity(for: .appleWatchSimilarToLeadI)?.doubleValue(for: .voltUnit(with: .milli)) == -0.125)
        let leadless = try StoredSampleFixtures.voltageMeasurement(offset: .nan, millivolts: nil)
        #expect(leadless.timeSinceSampleStart.isNaN)
        #expect(leadless.quantity(for: .appleWatchSimilarToLeadI) == nil)
    }

    @Test("Each corpus builder states a payload HealthKit refuses at creation, and the sample's facts")
    func corpusBuildersStateTheirPayloads() throws {
        let facts = GoldenCase.seriesFacts(uuid: 0xF3, duration: 60)
        let steps = try StoredSampleFixtures.quantitySample(HKQuantityType(.stepCount), value: -1, unit: .count(), facts: facts)
        #expect(steps.quantity.doubleValue(for: .count()) == -1)
        #expect(steps is HKCumulativeQuantitySample)
        let sleep = try StoredSampleFixtures.categorySample(HKCategoryType(.sleepAnalysis), value: 99, facts: facts)
        #expect(sleep.value == 99)
        let systolic = try StoredSampleFixtures.quantitySample(HKQuantityType(.bloodPressureSystolic), value: 120, unit: .millimeterOfMercury(), facts: facts)
        let pressure = try StoredSampleFixtures.correlation(HKCorrelationType(.bloodPressure), objects: [systolic], facts: facts)
        #expect(pressure.objects.map(\.sampleType) == [HKQuantityType(.bloodPressureSystolic)])
        let distance = StoredSampleFixtures.WorkoutStatistic(
            type: HKQuantityType(.distanceWalkingRunning), unit: .meterUnit(with: .kilo), sum: 10.5, average: nil, minimum: nil, maximum: nil
        )
        let workout = try StoredSampleFixtures.workout(activity: 9_999, duration: .nan, statistics: [distance], facts: facts)
        #expect(workout.workoutActivityType.rawValue == 9_999)
        #expect(workout.duration.isNaN)
        let meters = try #require(workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()))
        #expect(abs(meters - 10_500) < 1e-6)
        let reflection = try StoredSampleFixtures.stateOfMind(kind: 99, valence: 0.25, labels: [999], associations: [], facts: facts)
        #expect(reflection.kind.rawValue == 99)
        #expect(reflection.labels.map(\.rawValue) == [999])
        let assessment = try #require(try StoredSampleFixtures.scoredAssessment(.GAD7, score: 99, facts: facts))
        #expect(assessment.score == 99)
        for sample in [steps, sleep, pressure, workout, reflection, assessment] as [HKSample] {
            try Self.expectStored(sample, uuid: GoldenFixtures.uuid(0xF3))
            #expect(sample.endDate == facts.end)
        }
        #expect(throws: StoredSampleFixtures.FixtureError.self) {
            try StoredSampleFixtures.quantitySample(HKQuantityType(.stepCount), value: 1, unit: .meter(), facts: facts)
        }
    }

    @Test("A sample from a public initializer takes the chosen UUID and writer, and keeps them through an archive")
    func publicInitializerSamplesAreStorable() throws {
        let sample = try GoldenFixtures.heartRate(uuid: Self.uuid, device: GoldenFixtures.watch, writer: Self.writer)
        try Self.expectStored(sample)
        #expect(sample.quantity.doubleValue(for: GoldenFixtures.beatsPerMinute) == 72)
        #expect(sample.device == GoldenFixtures.watch)
        #expect(sample.metadata?[HKMetadataKeyTimeZone] as? String == GoldenFixtures.timeZone)

        let restored = try Self.archived(sample, as: HKQuantitySample.self)
        try Self.expectStored(restored)
        #expect(restored.device?.localIdentifier == GoldenFixtures.watch.localIdentifier)
        #expect(restored.metadata?[HKMetadataKeyTimeZone] as? String == GoldenFixtures.timeZone)

        let category = try GoldenFixtures.category(.sleepAnalysis, value: 1, uuid: Self.uuid, duration: 60)
        #expect(category.uuid == Self.uuid)
        let correlation = try GoldenCase.bloodPressure()
        #expect(correlation.uuid == GoldenFixtures.uuid(9))
        #expect(correlation.objects.map(\.uuid).sorted { $0.uuidString < $1.uuidString } == [GoldenFixtures.uuid(0x91), GoldenFixtures.uuid(0x92)])
        let workout = try StoredSampleFixtures.stored(GoldenFixtures.workout(withEvents: true), uuid: Self.uuid, writer: Self.writer)
        try Self.expectStored(workout)
        #expect(workout.workoutEvents?.count == 12)
    }

    @Test("A series class without a public initializer takes every one of its facts, and keeps them through an archive")
    func seriesSamplesAreConstructible() throws {
        let facts = GoldenCase.seriesFacts(uuid: 0xF0, duration: 30)
        let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts)
        let ecg = try StoredSampleFixtures.seriesSample(HKElectrocardiogram.self, sampleType: HKObjectType.electrocardiogramType(), facts: facts)
        let route = try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), facts: facts)
        for sample in [series, ecg, route] as [HKSample] {
            try Self.expectStored(sample)
            #expect(sample.startDate == facts.start)
            #expect(sample.endDate == facts.end)
            #expect(sample.device == facts.device)
            #expect(sample.metadata?[HKMetadataKeyTimeZone] as? String == GoldenFixtures.timeZone)
        }
        #expect(series.sampleType == HKSeriesType.heartbeat())
        #expect(ecg.sampleType == HKObjectType.electrocardiogramType())
        #expect(route.sampleType == HKSeriesType.workoutRoute())
        #expect(HealthKitSourceType(series) == .heartbeatSeries)
        #expect(HealthKitSourceType(ecg) == .electrocardiogram)
        #expect(HealthKitSourceType(route) == .workoutRoute)

        let restored = try Self.archived(series, as: HKHeartbeatSeriesSample.self)
        try Self.expectStored(restored)
        #expect(restored.startDate == facts.start)
        #expect(restored.sampleType == HKSeriesType.heartbeat())
    }

    @Test("The chosen UUID and writer are what the converter sees")
    func converterReadsTheStoredFacts() throws {
        let sample = try GoldenFixtures.heartRate(uuid: Self.uuid, device: GoldenFixtures.watch, writer: Self.writer)
        var inputs = ExportInputs.applicationWriter
        inputs.sequence = 250
        let conversion = try ExporterFixtures.export(sample, inputs).primary

        #expect(conversion.source.uuid == Self.uuid)
        let expectedRecord = try inputs.base.identityScope.sourceRecord(
            adapterID: HealthKitAssembly.adapter.adapterID,
            sourceType: HealthKitSourceType.heartRate.rawValue,
            repositoryScope: inputs.base.repositoryScope,
            nativeRecordID: Self.uuid.uuidString.lowercased()
        ).identifier
        #expect(conversion.identifiers.sourceRecord == expectedRecord)

        let writerSnapshot = try #require(conversion.identifiers.writerSnapshot)
        let writer = try #require(conversion.graph.resource(Device.self, at: writerSnapshot))
        #expect(writer.deviceName?.first?.name.value?.string == Self.writer.name)
        #expect(writer.identifier?.last?.value?.value?.string == Self.writer.bundleIdentifier)
        let writerHostSnapshot = try #require(conversion.identifiers.writerHostSnapshot)
        let writerHost = try #require(conversion.graph.resource(Device.self, at: writerHostSnapshot))
        #expect(writerHost.modelNumber?.value?.string == Self.writer.productType)
        #expect(writerHost.version?.first?.value.value?.string == "26.1.0")
    }
}

#endif
