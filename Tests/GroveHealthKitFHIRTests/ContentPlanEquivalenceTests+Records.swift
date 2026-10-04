//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


extension ContentPlanEquivalenceTests {
    @Test("The workout plan states today's value of every activity, and today's components in today's order and units")
    func workoutIsTodays() throws {
        guard case .workout(let content)? = Self.observationPlan(.workout)?.value else {
            Issue.record("Workouts convert through no workout content")
            return
        }
        for raw in Array(0...100) + [3_000, 3_001] {
            guard let activity = HKWorkoutActivityType(rawValue: UInt(raw)) else {
                continue
            }
            #expect(try HealthKitConverter.workoutValue(activityType: activity) == content.activity(activity.rawValue).value)
            #expect(HealthKitConverter.distanceType(for: activity) == content.activity(activity.rawValue).distance)
        }
        // Every statistic in a unit other than the one it is read in, so reading it in another unit would show.
        let statistics = [
            Self.total(.distanceWalkingRunning, 1_000, .foot()), Self.total(.distanceCycling, 12, .mile()),
            Self.total(.distanceSwimming, 800, .yard()), Self.total(.activeEnergyBurned, 500, .jouleUnit(with: .kilo)),
            Self.total(.stepCount, 1_200, .count()), Self.total(.flightsClimbed, 3, .count()), Self.total(.swimmingStrokeCount, 40, .count()),
            StoredSampleFixtures.WorkoutStatistic(
                type: HKQuantityType(.heartRate),
                unit: .count().unitDivided(by: .second()),
                sum: nil,
                average: 2,
                minimum: 1.5,
                maximum: 3
            )
        ]
        for activity in [HKWorkoutActivityType.running, .cycling, .swimming, .yoga] {
            for stated in [statistics, []] {
                let workout = try StoredSampleFixtures.workout(activity: activity.rawValue, duration: 1_800.5, statistics: stated, facts: ContentPlanSamples.facts())
                #expect(try HealthKitConverter.workoutComponents(workout) == Self.components(content, of: workout), "\(activity.rawValue)")
            }
        }
    }

    @Test("The State of Mind plan states today's components for every kind, valence, label and association, and today's valence")
    func stateOfMindIsTodays() throws {
        guard case .stateOfMind(let content)? = Self.observationPlan(.stateOfMind)?.value else {
            Issue.record("States of mind convert through no State of Mind content")
            return
        }
        let happy = HKStateOfMind.Label.happy.rawValue
        let work = HKStateOfMind.Association.work.rawValue
        let reflections = try [0, 1, 2, 99].map { try Self.reflection(kind: $0) }
            + [-1, -0.7, -0.4, -0.1, 0, 0.1, 0.4, 0.7, 1].map { try Self.reflection(valence: $0) }
            + [Array(0...41) + [999], [happy, happy, HKStateOfMind.Label.angry.rawValue]].map { try Self.reflection(labels: $0) }
            + [Array(0...21) + [999], [work, work, HKStateOfMind.Association.family.rawValue]].map { try Self.reflection(associations: $0) }
        for reflection in reflections {
            var planned = [content.kinds[reflection.kind], content.classifications[reflection.valenceClassification]].compactMap(\.self)
            planned += reflection.labels.compactMap { content.labels[$0] }.sorted { $0.code < $1.code }.map(\.component)
            planned += reflection.associations.compactMap { content.associations[$0] }.sorted { $0.code < $1.code }.map(\.component)
            #expect(try HealthKitConverter.stateOfMindComponents(reflection) == planned)
            #expect(try HealthKitConverter.stateOfMindValue(reflection) == content.valence.quantity(reflection.valence))
        }
    }

    @Test("The ECG plan states today's waveform, lead, voltage origin, classifications, algorithm versions and average heart rate")
    func electrocardiogramIsTodays() throws {
        guard case .electrocardiogram(let content) = HealthKitContentPlan[.electrocardiogram].route else {
            Issue.record("ECGs convert through no ECG content")
            return
        }
        let waveform = try HealthKitConverter.ecgObservation(input: try Self.ecgInput())
        #expect(waveform.code == content.waveformSkeleton.code && waveform.status == content.waveformSkeleton.status)
        #expect(waveform.meta == content.waveformSkeleton.meta && waveform.category == content.waveformSkeleton.category)
        #expect(waveform.extension?.first == content.waveformSkeleton.extension?.first && content.waveformSkeleton.extension?.count == 1)
        let voltages = try #require(waveform.component?.first)
        #expect(voltages.code == content.lead)
        guard case .sampledData(let data)? = voltages.value else {
            Issue.record("The ECG states no SampledData")
            return
        }
        #expect(data.origin == content.voltageOrigin)
        #expect(content.voltageUnit == .voltUnit(with: .milli), "today reads the voltages in mV")
        for raw in -1...255 {
            if let classification = HKElectrocardiogram.Classification(rawValue: raw) {
                let today = try? HealthKitConverter.ecgObservation(input: try Self.ecgInput(classification: classification))
                #expect(today?.interpretation?.first == content.classifications[classification], "\(raw)")
            }
            let today = try? HealthKitConverter.ecgObservation(input: try Self.ecgInput(algorithmVersion: raw))
            #expect(today?.method == content.algorithmVersions[raw], "\(raw)")
        }
        let child = try #require(try HealthKitConverter.ecgAverageHeartRateChild(input: try Self.ecgInput(averageHeartRate: 72)))
        guard case .observation(let heartRate) = child.resource, case .quantity(var quantity)? = heartRate.value else {
            Issue.record("The ECG's average heart rate states no Quantity")
            return
        }
        let skeleton = content.averageHeartRateSkeleton
        #expect(heartRate.code == skeleton.code && heartRate.status == skeleton.status && heartRate.meta == skeleton.meta)
        #expect(heartRate.category == skeleton.category && heartRate.extension == skeleton.extension)
        quantity.value = nil
        #expect(quantity == content.averageHeartRateQuantity.empty)
        #expect(content.averageHeartRateQuantity.domain == nil)
    }

    @Test("Every document plan states today's profiles, status, type, source-type extension, format and title")
    func documentsAreTodays() throws {
        let context = HealthKitConversionContext(routeDisclosurePolicy: .authorized)
        let assembly = HealthKitAssembly(context: context.event)
        let request = HealthKitAssembly.Request(context: context)
        let facts = ContentPlanSamples.facts()
        let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts)
        let beats = [HealthKitHeartbeat(timeSinceSeriesStart: 0.5, precededByGap: false)]
        let heartbeat = try assembly.convertHeartbeatSeries(HealthKitHeartbeatSeriesRecord(series: series, heartbeats: beats), request: request)
        Self.expectDocument(heartbeat.document, of: .heartbeatSeries)
        let route = try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), facts: facts)
        let fix = CLLocation(latitude: 37.4, longitude: -122.1)
        let track = try #require(try assembly.convertWorkoutRoute(HealthKitWorkoutRouteRecord(route: route, locations: [fix]), request: request))
        Self.expectDocument(track.document, of: .workoutRoute)
        #if !os(watchOS)
        // A blank title: the document is carried under the plan's.
        let cda = try StoredSampleFixtures.cdaDocument(title: "  ", document: Data(GoldenCase.clinicalDocumentXML.utf8), facts: facts)
        Self.expectDocument(try HealthKitConverter.convertSample(cda, context: context).document, of: .cda)
        for type in HealthKitContentPlan.all.map(\.sourceType) where type.rawValue.hasPrefix("HKClinicalTypeIdentifier") {
            let clinicalType = try #require(HKObjectType.clinicalType(forIdentifier: HKClinicalTypeIdentifier(rawValue: type.rawValue)))
            let resource = Data(ContentCorpusGrid.clinicalResource.utf8)
            let release = try HKFHIRVersion(fromVersionString: "4.0.1")
            let record = try StoredSampleFixtures.clinicalRecord(clinicalType, fhirVersion: release, resource: resource, facts: facts)
            Self.expectDocument(try HealthKitConverter.convertSample(record, context: context).document, of: type)
        }
        #endif
    }
}


extension ContentPlanEquivalenceTests {
    /// A workout total of `sum` in `unit`.
    private static func total(_ type: HKQuantityTypeIdentifier, _ sum: Double, _ unit: HKUnit) -> StoredSampleFixtures.WorkoutStatistic {
        StoredSampleFixtures.WorkoutStatistic(type: HKQuantityType(type), unit: unit, sum: sum, average: nil, minimum: nil, maximum: nil)
    }

    /// The components of a workout as the workout content states them: each statistic reads what it says it reads,
    /// so the helper encodes no order, quantity type or fallback of its own.
    private static func components(_ content: HealthKitWorkoutContent, of workout: HKWorkout) throws -> [ObservationComponent] {
        var components = [try content.activeDuration.component(workout.duration)]
        let activity = content.activity(workout.workoutActivityType.rawValue)
        for statistic in content.statistics {
            let statistics = workout.statistics(for: HKQuantityType(statistic.quantityType(of: activity)))
            guard let quantity = statistics.flatMap(statistic.read) else {
                continue
            }
            components.append(try statistic.template.component(quantity.doubleValue(for: statistic.unit)))
        }
        return components
    }

    /// A reflection of the given kind, valence, labels and associations.
    private static func reflection(kind: Int = 1, valence: Double = 0.5, labels: [Int] = [], associations: [Int] = []) throws -> HKStateOfMind {
        try StoredSampleFixtures.stateOfMind(kind: kind, valence: valence, labels: labels, associations: associations, facts: ContentPlanSamples.facts())
    }

    /// The evidence of a valid four-point ECG in UTC, stating the given source facts.
    private static func ecgInput(
        classification: HKElectrocardiogram.Classification = .sinusRhythm,
        algorithmVersion: Int? = nil,
        averageHeartRate: Double? = nil
    ) throws -> HealthKitECGObservationInput {
        let points = [0.250, 0.252, 0.254, 0.256].enumerated().map { index, offset in
            HealthKitECGVoltagePoint(timeSinceSampleStart: offset, millivolts: Double(index))
        }
        let source = HealthKitECGSourceEvidence(
            sourceTypeIdentifier: HealthKitContract.electrocardiogramSourceTypeIdentifier,
            startDate: ContentPlanSamples.start,
            endDate: ContentPlanSamples.start.addingTimeInterval(30),
            timeZone: .gmt,
            classification: classification,
            symptomsStatus: .none,
            numberOfVoltageMeasurements: points.count,
            averageHeartRate: averageHeartRate,
            samplingFrequency: 500,
            algorithmVersion: algorithmVersion
        )
        let waveform = try HealthKitECGEvidenceValidator.validateWaveform(reportedCount: points.count, samplingFrequencyHertz: 500, points: points)
        return HealthKitECGObservationInput(source: source, waveform: waveform, symptomOutputIdentifiers: [])
    }

    /// Checks today's document of `type` against the type's document plan.
    private static func expectDocument(_ today: DocumentReference, of type: HealthKitSourceType) {
        let plan: DocumentPlan
        switch HealthKitContentPlan[type].route {
        case .recording(let document), .clinical(let document):
            plan = document
        default:
            Issue.record("\(type.rawValue) converts through no document plan")
            return
        }
        #expect(today.meta == plan.skeleton.meta && today.status == plan.skeleton.status, "\(type.rawValue)")
        #expect(today.type == plan.skeleton.type && today.extension == plan.skeleton.extension, "\(type.rawValue)")
        #expect(today.content.first?.format == plan.formatCoding, "\(type.rawValue)")
        #expect(today.content.first?.attachment.title?.value?.string == plan.title, "\(type.rawValue)")
    }
}

#endif
