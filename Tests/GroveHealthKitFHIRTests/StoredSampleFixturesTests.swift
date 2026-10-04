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

    private static func expectStored(_ sample: HKSample, sourceLocation: SourceLocation = #_sourceLocation) throws {
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

    @Test("A series class without a public initializer takes every fact of its shape, and keeps them through an archive")
    func seriesSamplesAreConstructible() throws {
        let shape = GoldenCase.seriesShape(uuid: 0xF0, duration: 30)
        let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), shape: shape)
        let ecg = try StoredSampleFixtures.seriesSample(HKElectrocardiogram.self, sampleType: HKObjectType.electrocardiogramType(), shape: shape)
        let route = try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), shape: shape)
        for sample in [series, ecg, route] as [HKSample] {
            try Self.expectStored(sample)
            #expect(sample.startDate == shape.start)
            #expect(sample.endDate == shape.end)
            #expect(sample.device == shape.device)
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
        #expect(restored.startDate == shape.start)
        #expect(restored.sampleType == HKSeriesType.heartbeat())
    }

    @Test("The chosen UUID and writer are what the converter sees")
    func converterReadsTheStoredFacts() throws {
        let sample = try GoldenFixtures.heartRate(uuid: Self.uuid, device: GoldenFixtures.watch, writer: Self.writer)
        let context = try GoldenFixtures.context(sequence: 250, .applicationWriter)
        let conversion = try HealthKitConverter().convert(sample, context: context).primary

        #expect(conversion.source.uuid == Self.uuid)
        let expectedRecord = try context.event.identityScope.sourceRecord(
            adapterID: HealthKitConverter.adapterID,
            sourceType: HealthKitSourceType.heartRate.rawValue,
            repositoryScope: context.event.repositoryScope,
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
