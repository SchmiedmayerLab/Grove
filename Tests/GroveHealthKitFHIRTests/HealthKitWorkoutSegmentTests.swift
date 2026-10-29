//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HealthKitWorkoutSegmentTests {
    @Test(arguments: [
        (808_963_200.0009765625, "2026-08-21T00:00:00.000976562Z"),
        (808_963_200.0029296875, "2026-08-21T00:00:00.002929688Z"),
        (808_963_200.10000002384185791015625, "2026-08-21T00:00:00.100000024Z"),
        (-0.1, "2000-12-31T23:59:59.900000000Z")
    ])
    func identityInstantsMatchTheGuide(seconds: Double, expected: String) throws {
        #expect(try HealthKitWorkoutSegmentIdentity.instant(Date(timeIntervalSinceReferenceDate: seconds)) == expected)
    }

    @Test
    func allEventsAndActivitiesCarryTheSessionContext() throws {
        let original = GoldenFixtures.workout(withEvents: true, device: GoldenFixtures.watch, userEntered: true)
        var metadata = original.metadata ?? [:]
        metadata[HKMetadataKeySyncIdentifier] = "workout-with-segments"
        metadata[HKMetadataKeySyncVersion] = 3
        let sample = try StoredSampleFixtures.stored(
            StoredSampleFixtures.withMetadata(original, metadata),
            uuid: GoldenFixtures.uuid(0xC1),
            writer: GoldenFixtures.foreignWriter
        )
        var inputs = ExportInputs.applicationWriter
        inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        let conversion = try AssemblyFixtures.conversion(sample, inputs)
        let entries = try #require(conversion.graph.bundle.entry)
        let observations = entries.compactMap { $0.resource?.get(if: Observation.self) }
        let session = try #require(observations.first)
        let count = (sample.workoutEvents ?? []).count + sample.workoutActivities.count
        #expect(observations.count == count + 1)
        #expect(session.hasMember?.count == count)
        let childURLs = entries.dropFirst().compactMap { entry in
            entry.resource?.get(if: Observation.self).map { _ in entry.fullUrl?.value?.url.absoluteString }
        }
        #expect(session.hasMember?.map { $0.reference?.value?.string } == childURLs)
        let writer = session.identifier?.filter { (try? RoledIdentifier($0).role) == .writerRecord }
        try #require(writer?.isEmpty == false)
        for child in observations.dropFirst() {
            #expect(child.meta?.profile == [Profile.groveMobileWorkoutSegment, Profile.healthkitObservation])
            #expect(child.subject == session.subject)
            #expect(child.device == session.device)
            #expect(child.identifier?.filter { (try? RoledIdentifier($0).role) == .writerRecord } == writer)
            #expect(child.identifier?.contains { $0.system?.value?.url.absoluteString == GoldenFixtures.nativeIdentifierSystem.rawValue } == false)
            for url in [Canonicals.recordingMethod, Canonicals.writerRecordVersion] {
                #expect(child.extension?.filter { $0.url == url } == session.extension?.filter { $0.url == url })
            }
        }
    }

    @Test
    func duplicateEventsHaveDistinctStableIdentitiesWithoutDuplicatingActivityEvents() throws {
        let base = GoldenFixtures.workout(withEvents: false)
        let event = HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: base.startDate, duration: 30), metadata: nil)
        let workout = HKWorkout(
            activityType: .running,
            start: base.startDate,
            end: base.endDate,
            workoutEvents: [event, event],
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: base.metadata
        )
        let content = try HealthKitWorkoutContent(MeasurementCatalog.workout)
        let metadata = HealthKitSampleMetadata(workout, rule: HealthKitContentPlan[.workout].metadata)
        let outputs = try content.segments(workout, metadata: metadata)
        #expect(outputs.count == 2 + workout.workoutActivities.count)
        #expect(outputs[0].discriminator.hasSuffix("|event|3|0"))
        #expect(outputs[1].discriminator.hasSuffix("|event|3|1"))
        #expect(outputs[0].discriminator != outputs[1].discriminator)
    }

    @Test
    func unknownSDKValuesKeepTheirRawValues() throws {
        let base = GoldenFixtures.workout(withEvents: false)
        let event = HKWorkoutEvent(
            type: .lap,
            dateInterval: DateInterval(start: base.startDate, duration: 0),
            metadata: nil
        )
        let workout = HKWorkout(
            activityType: .running,
            start: base.startDate,
            end: base.endDate,
            workoutEvents: [event],
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: base.metadata
        )
        // The factories reject future SDK values, even though stored samples can carry them.
        try StoredSampleFixtures.restate(event, with: ["type": 999])
        try StoredSampleFixtures.restate(workout, with: ["workoutActivityType": 999])
        let stored = try StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(0xC3))
        let conversion = try AssemblyFixtures.conversion(stored)
        let observations = conversion.graph.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        #expect(observations.count == 2 + workout.workoutActivities.count)
        for observation in observations.prefix(2) {
            guard case .codeableConcept(let value)? = observation.value else {
                Issue.record("Every workout output must retain its classification")
                continue
            }
            #expect(value.coding?.count == 1)
            #expect(observation.extension?.first { $0.url == Canonicals.healthKitUnmappedSourceValue }?.value == .string("999".asFHIRStringPrimitive()))
        }
    }

    @Test(arguments: [false, true])
    func invalidActivityRefusesTheWholeWorkout(missingEnd: Bool) async throws {
        let base = GoldenFixtures.workout(withEvents: false)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        let activity = HKWorkoutActivity(
            workoutConfiguration: configuration,
            start: base.startDate,
            end: missingEnd ? nil : base.endDate.addingTimeInterval(1),
            metadata: nil
        )
        let workout = try StoredSampleFixtures.workout(base, activities: [(activity, [])])
        let stored = try StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(0xC2))
        let failure: HealthKitConversionError.ValueFailure = missingEnd ? .workoutActivityEndMissing : .effectivePeriodInvalid
        await #expect(throws: HealthKitConversionError.invalidValue(.workout, failure)) {
            try await ExporterFixtures.export(stored)
        }
    }
}

#endif
