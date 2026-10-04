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


/// Seeded random records for oracle O4, drawn as corpus inputs so `ContentCorpusSamples` builds them exactly as it
/// builds the corpus's: Observation samples of every kind of value rule, ECG records and every document record.
///
/// Every fault (a zone, an interval, an instant, a value, a metadata value; for an ECG, each of its checks) is drawn
/// independently, so a refused record often states several, and which one each builder reports pins the order its
/// checks run in. A counted fault is one the record would be refused for on its own: a value the template refuses, a
/// statistic the activity reads, a metadata value the component refuses. Values are drawn finer than any rounding a
/// builder could slip in (durations, beat times and member readings with fractions). Only values HealthKit can hold
/// are drawn: a valence inside -1...1, years before 4000 wherever a sample is created from one.
struct ContentBuilderRandomRecords {
    /// How many records a run draws.
    static let count = 6_000

    /// Every Observation plan with its source type, grouped by what its value rule reads; the types that state a
    /// metadata component, and the coded types with values no normative code states (walking steadiness), form groups
    /// of their own. Each group is drawn equally often, so the rules only a few types share (blood pressure, workouts,
    /// State of Mind, protection, durations, metadata components) are drawn as often as the quantities and codes most
    /// types share.
    private static let observationGroups: [[(type: HealthKitSourceType, plan: ObservationPlan)]] = {
        let plans = HealthKitContentPlan.all.compactMap { plan -> (type: HealthKitSourceType, plan: ObservationPlan)? in
            guard case .observation(let observation) = plan.route else {
                return nil
            }
            return (plan.sourceType, observation)
        }
        let groups = Dictionary(grouping: plans) { entry in
            if entry.plan.metadataComponent != nil {
                return "metadata component"
            }
            if case let .coded(_, unresolved) = entry.plan.value, !unresolved.isEmpty {
                return "unresolved"
            }
            return Mirror(reflecting: entry.plan.value).children.first?.label ?? ""
        }
        return groups.keys.sorted().compactMap { groups[$0] }
    }()

    /// Every clinical record type.
    private static let clinicalTypes = HealthKitContentPlan.all.map(\.sourceType.rawValue).filter { $0.hasPrefix("HKClinicalTypeIdentifier") }

    /// Zones a sample may name, and names that are no zone.
    private static let zones: [ContentCorpusMetadataValue] = ["America/Los_Angeles", "Asia/Kolkata", "Asia/Kathmandu", "America/St_Johns", "UTC"]
        .map(ContentCorpusMetadataValue.string)
    /// Zone metadata no conversion admits.
    private static let invalidZones: [ContentCorpusMetadataValue] = [.string("Not/A-Time-Zone"), .integer(3)]
    /// The values of each metadata key an Observation component reads (`nil` for none): those its component admits,
    /// and those it refuses. A motion context is optional and read only as a number, so a string states no component;
    /// an insulin delivery reason must be a number it names; a cycle start a Boolean.
    private static let componentMetadata: KeyValuePairs<String, (valid: [ContentCorpusMetadataValue?], invalid: [ContentCorpusMetadataValue?])> = [
        HKMetadataKeyHeartRateMotionContext: ([nil, .integer(0), .integer(1), .integer(2), .string("active")], [.integer(7)]),
        HKMetadataKeyInsulinDeliveryReason: ([.integer(1), .integer(2)], [nil, .integer(0), .integer(9), .string("bolus")]),
        HKMetadataKeyMenstrualCycleStart: ([.boolean(true), .boolean(false)], [nil, .integer(2), .string("yes")])
    ]
    /// Workout statistics of distinct types: the session totals and heart rate, and every other distance type.
    private static let workoutStatistics = (ContentCorpusGrid.workoutStatistics.first { $0.0 == "all" }?.1 ?? [])
        + ContentCorpusGrid.distanceStatistics.filter { $0.type != HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue }

    /// The draw.
    private var generator: HealthKitEffectiveTimeTests.SeededGenerator
    /// The faults the current record was drawn with.
    private var faults = 0

    /// The records `seed` draws.
    init(seed: UInt64) {
        generator = HealthKitEffectiveTimeTests.SeededGenerator(state: seed)
    }

    /// The next record, and how many faults it was drawn with.
    mutating func next() -> (source: ContentCorpusSource, faults: Int) {
        faults = 0
        let roll = Int.random(in: 0..<20, using: &generator)
        let source = switch roll {
        case 0..<12: observationRecord()
        case 12..<16: electrocardiogramRecord()
        default: documentRecord()
        }
        return (source, faults)
    }

    /// One of `choices`.
    private mutating func pick<Element>(_ choices: [Element]) -> Element {
        choices[Int.random(in: choices.indices, using: &generator)]
    }

    /// Whether to draw a fault, one time in `odds`; a drawn fault is counted.
    private mutating func fault(oneIn odds: Int = 4) -> Bool {
        guard Int.random(in: 0..<odds, using: &generator) == 0 else {
            return false
        }
        faults += 1
        return true
    }

    /// Whether a coin lands heads.
    private mutating func coin() -> Bool {
        Bool.random(using: &generator)
    }

    /// A value in `range` to the hundredth.
    private mutating func hundredths(in range: ClosedRange<Double>) -> Double {
        (Double.random(in: range, using: &generator) * 100).rounded() / 100
    }

    /// A start between 2000 and 2030, or, as a fault, in the year 10000, which no FHIR date-time states.
    private mutating func start() -> Double {
        guard fault(oneIn: 12) else {
            return Double.random(in: 946_684_800...1_893_456_000, using: &generator)
        }
        return 253_402_300_800 + Double(Int.random(in: 0..<86_400, using: &generator))
    }

    /// The zone metadata: a zone, none, or, as a fault, a name that is no zone.
    private mutating func zone() -> ContentCorpusMetadataValue? {
        if fault() {
            return pick(Self.invalidZones)
        }
        return coin() ? pick(Self.zones) : nil
    }
}


extension ContentBuilderRandomRecords {
    /// A sample of a random Observation plan: its value drawn for its value rule, its interval (seconds to hours, so a
    /// duration is rarely a whole number of minutes) for its effective rule, and every metadata key a component reads.
    private mutating func observationRecord() -> ContentCorpusSource {
        let (type, plan) = pick(pick(Self.observationGroups))
        let start = start()
        var end = start
        if case let .interval(nonZero) = plan.effective {
            end += fault() ? pick(nonZero ? [0, -30] : [-30]) : Double.random(in: 1...5_400, using: &generator)
        }
        var metadata: [String: ContentCorpusMetadataValue] = [:]
        metadata[HKMetadataKeyTimeZone] = zone()
        for (key, values) in Self.componentMetadata {
            if plan.metadataComponent?.field.key == key {
                metadata[key] = fault(oneIn: 2) ? pick(values.invalid) : pick(values.valid)
            } else if coin() {
                metadata[key] = pick(values.valid.compactMap(\.self))
            }
        }
        metadata[HKMetadataKeyWasUserEntered] = coin() ? .boolean(coin()) : nil
        let record = value(of: type, plan.value, metadata: &metadata)
        return ContentCorpusSource(record: record, start: start, end: end, metadata: metadata, device: nil, writer: .unattributed, context: .plain)
    }

    /// A record of `type` whose value is drawn for `rule`: one it admits, or, as a fault, one it refuses.
    private mutating func value(
        of type: HealthKitSourceType,
        _ rule: ValueRule,
        metadata: inout [String: ContentCorpusMetadataValue]
    ) -> ContentCorpusRecord {
        switch rule {
        case let .quantity(template, read):
            return quantity(of: type, template: template, read: read)
        case let .coded(values, unresolved):
            let valid = values.keys.sorted()
            // A type none of whose values resolves (walking steadiness) is refused for any value.
            faults += valid.isEmpty ? 1 : 0
            let raw = valid.isEmpty || fault() ? pick(unresolved.sorted() + [-1, 9, 99]) : pick(valid)
            return .category(type: type.rawValue, value: raw)
        case .duration:
            return .category(type: type.rawValue, value: fault() ? 1 : 0)
        case .protection:
            let key = HKMetadataKeySexualActivityProtectionUsed
            metadata[key] = fault() ? .string("yes") : pick([.boolean(true), .boolean(false), nil])
            return .category(type: type.rawValue, value: fault() ? 2 : 0)
        case .bloodPressure:
            return bloodPressure()
        case .workout(let content):
            return workout(content)
        case .stateOfMind:
            let labels = (0..<Int.random(in: 0...4, using: &generator)).map { _ in pick(Array(0...41) + [999]) }
            let associations = (0..<Int.random(in: 0...4, using: &generator)).map { _ in pick(Array(0...21) + [999]) }
            let valence = (Double.random(in: -1...1, using: &generator) * 100).rounded() / 100
            return .stateOfMind(kind: pick([0, 1, 2, 99]), valence: valence, labels: labels, associations: associations)
        }
    }

    /// A quantity of `type` read as `read`: a value inside the template's domain, or, as a fault, one it refuses.
    private mutating func quantity(of type: HealthKitSourceType, template: QuantityTemplate, read: QuantityRead) -> ContentCorpusRecord {
        let domain = template.domain
        let low = domain.map { NSDecimalNumber(decimal: $0.minimum.value).doubleValue } ?? 0
        let high = domain?.maximum.map { NSDecimalNumber(decimal: $0.value).doubleValue } ?? low + 1_000
        var value = Double.random(in: low...high, using: &generator)
        value = domain?.integerOnly == true ? value.rounded() : (value * 1_000).rounded() / 1_000
        var refused = domain.map { [low - 1] + ($0.maximum == nil ? [] : [high + 1]) } ?? []
        if case .score = read {
            // A score is a whole number, and one no number states is stated as -1: only a domain refuses a score.
        } else {
            refused += [.nan, .infinity, -.infinity, 1e300] + (domain?.integerOnly == true ? [low + 0.5] : [])
        }
        if !refused.isEmpty, fault() {
            value = pick(refused)
        }
        switch read {
        case .unit(let binding):
            return .quantity(type: type.rawValue, value: value, unit: binding.unit.unitString)
        case .platformRate:
            return .quantity(type: type.rawValue, value: value, unit: HKUnit.count().unitString)
        case .percent:
            return .quantity(type: type.rawValue, value: value / 100, unit: "%")
        case .score:
            return .assessment(type: type.rawValue, score: Int(exactly: value.rounded()) ?? -1)
        }
    }

    /// A blood-pressure correlation of both members, each read to the hundredth, or, as faults, a member reading no
    /// decimal states, or a member missing (the other member, when one reading is a fault, so both faults stand).
    private mutating func bloodPressure() -> ContentCorpusRecord {
        var members = [
            ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue, value: hundredths(in: 90...200)),
            ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue, value: hundredths(in: 40...130))
        ]
        var refusedReading: Int?
        if fault() {
            let index = Int.random(in: 0...1, using: &generator)
            members[index].value = pick([.nan, .infinity, 1e300])
            refusedReading = index
        }
        if fault() {
            members.remove(at: refusedReading.map { 1 - $0 } ?? Int.random(in: 0...1, using: &generator))
        }
        return .correlation(type: HKCorrelationTypeIdentifier.bloodPressure.rawValue, members: members.shuffled(using: &generator))
    }

    /// A workout of any activity lasting up to two hours to the hundredth of a second, with any statistics, and, as
    /// faults, a duration or a statistic the activity reads that no decimal states.
    private mutating func workout(_ content: HealthKitWorkoutContent) -> ContentCorpusRecord {
        let activity: UInt = pick(Array(0...90) + [3_000, 9_999])
        var statistics = Self.workoutStatistics.filter { _ in coin() }
        let read = Set(content.statistics.map { $0.quantityType(of: content.activity(activity)).rawValue })
        let readable = statistics.indices.filter { read.contains(statistics[$0].type) }
        if !readable.isEmpty, fault() {
            let index = pick(readable)
            statistics[index].sum = statistics[index].sum.map { _ in .nan }
            statistics[index].average = statistics[index].average.map { _ in .nan }
        }
        let duration = fault() ? .nan : hundredths(in: 0...7_200)
        return .workout(activity: activity, duration: duration, statistics: statistics)
    }
}


extension ContentBuilderRandomRecords {
    /// An ECG record from the corpus's sinus-rhythm reading, each of its checks drawn to fail on its own.
    private mutating func electrocardiogramRecord() -> ContentCorpusSource {
        var reading = ContentCorpusGrid.electrocardiogramReading
        var source = ContentCorpusGrid.electrocardiogramSource(reading)
        electrocardiogramInterval(&source)
        if fault(oneIn: 8) {
            source.metadata[HKMetadataKeyTimeZone] = pick(Self.invalidZones)
        }
        source.metadata[HKMetadataKeyAppleECGAlgorithmVersion] = fault(oneIn: 8) ? .integer(3) : pick([.integer(1), .integer(2), nil])
        if fault(oneIn: 10) {
            reading.voltages = [reading.voltages[0]]
        }
        let index = Int.random(in: reading.voltages.indices, using: &generator)
        if fault(oneIn: 10) {
            reading.voltages[index].millivolts = pick([nil, .nan])
        }
        if fault(oneIn: 10) {
            reading.voltages[index].offset = pick([-0.002, .nan, 0.2, 0.2555])
        }
        reading.reportedCount = fault(oneIn: 10) ? pick([0, -1, 3, 5]) : reading.voltages.count
        reading.samplingFrequency = fault(oneIn: 10) ? pick([250, 0, .nan, -500]) : pick([500, nil])
        reading.classification = fault(oneIn: 10) ? 99 : pick([0, 1, 2, 3, 4, 5, 6, 100])
        reading.averageHeartRate = fault(oneIn: 10) ? pick([.nan, .infinity, 1e300]) : pick([72, 72.5, nil])
        symptoms(of: &reading)
        source.record = .electrocardiogram(reading: reading)
        return source
    }

    /// An ECG's 30-second interval from a start between 2000 and 2030 in a zone it names, or, as faults, ending before
    /// it starts, or starting late on 9999-12-31 in UTC, so its voltages, or only its end, fall into the year 10000
    /// (its voltages when it also ends before it starts, so both faults stand).
    private mutating func electrocardiogramInterval(_ source: inout ContentCorpusSource) {
        let reversed = fault(oneIn: 8)
        if fault(oneIn: 8) {
            source.start = reversed ? 253_402_300_799.9 : pick([253_402_300_799.9, 253_402_300_770])
            source.metadata[HKMetadataKeyTimeZone] = .string("UTC")
        } else {
            source.start = Double.random(in: 946_684_800...1_893_456_000, using: &generator)
            source.metadata[HKMetadataKeyTimeZone] = pick(Self.zones)
        }
        source.end = source.start + (reversed ? -30 : 30)
    }

    /// Symptoms as the status states them, each of a severity its code states, or, as faults, an unknown status, a
    /// status contradicting them, a severity no code states, a type the ECG does not admit, or a stated sample again
    /// (under its own type or another). Each faulty symptom lands at a random position, so which one is refused first
    /// pins the order the per-symptom checks run in; a symptom's severity is checked when it converts, after them all.
    private mutating func symptoms(of reading: inout ContentCorpusElectrocardiogram) {
        typealias Symptom = ContentCorpusElectrocardiogram.Symptom
        let admitted = [HKCategoryTypeIdentifier.chestTightnessOrPain, .fatigue, .dizziness].map(\.rawValue)
        let headache = HKCategoryTypeIdentifier.headache.rawValue
        let present = HKElectrocardiogram.SymptomsStatus.present.rawValue
        reading.symptomsStatus = fault(oneIn: 10) ? 99 : pick([0, 1, present, present])
        let stated = reading.symptomsStatus == present ? Int.random(in: 1...2, using: &generator) : 0
        var symptoms = (0..<stated).map { ordinal in
            Symptom(type: pick(admitted), value: fault(oneIn: 10) ? pick([-1, 5, 9]) : pick(Array(0...4)), ordinal: 0xE1 + UInt8(ordinal))
        }
        var faulty: [Symptom] = []
        if fault(oneIn: 3) {
            faulty.append(Symptom(type: headache, value: 2, ordinal: 0xE8))
        }
        if let first = symptoms.first, fault(oneIn: 3) {
            faulty.append(Symptom(type: pick(admitted + [headache]), value: 2, ordinal: first.ordinal))
        }
        for symptom in faulty {
            symptoms.insert(symptom, at: Int.random(in: 0...symptoms.count, using: &generator))
        }
        reading.symptoms = symptoms
        let agrees = (reading.symptomsStatus == present) != symptoms.isEmpty
        if reading.symptomsStatus != 99, agrees, fault(oneIn: 10) {
            reading.symptomsStatus = symptoms.isEmpty ? present : 1
        }
    }

    /// A heartbeat series, a route, a clinical record or a CDA document, each refused, as a fault, for an empty
    /// series, a reading the column schema cannot write, a release or payload not admitted, or no bytes. A document
    /// never reads a zone, so the one it names, valid or not, is no fault.
    private mutating func documentRecord() -> ContentCorpusSource {
        let record: ContentCorpusRecord
        switch Int.random(in: 0..<4, using: &generator) {
        case 0:
            var beats = fault(oneIn: 6) ? [] : heartbeats()
            if !beats.isEmpty, fault(oneIn: 6) {
                beats[0].offset = .nan
            }
            record = .heartbeatSeries(beats: beats)
        case 1:
            let fixes = ContentCorpusGrid.routeLocations + [ContentCorpusGrid.restingFix]
            var locations = fault(oneIn: 6) ? [] : fixes.filter { _ in coin() || coin() }
            if !locations.isEmpty, fault(oneIn: 6) {
                locations[0].latitude = .nan
            }
            record = .workoutRoute(locations: locations, disclosed: true)
        case 2:
            let resource = fault() ? pick([nil, "not json", "[1]"]) : ContentCorpusGrid.clinicalResource
            record = .clinicalRecord(type: pick(Self.clinicalTypes), fhirVersion: fault() ? "3.0.1" : pick(["1.0.2", "4.0.1"]), resource: resource)
        default:
            let document = fault() ? pick([nil, ""]) : GoldenCase.clinicalDocumentXML
            record = .cdaDocument(title: pick(["", "  ", "Visit Summary", "\n Notes \t"]), document: document)
        }
        let zone = coin() ? pick(Self.zones + Self.invalidZones) : nil
        return ContentCorpusSource(record, end: ContentCorpusGrid.start + 60, metadata: zone.map { [HKMetadataKeyTimeZone: $0] } ?? [:])
    }

    /// One to five beats, each a quarter second to two seconds after the one before in steps of 1/1024 s, so most beat
    /// times fall between two milliseconds.
    private mutating func heartbeats() -> [ContentCorpusBeat] {
        var offset = 0.0
        return (0..<Int.random(in: 1...5, using: &generator)).map { _ in
            offset += Double(Int.random(in: 256...2_048, using: &generator)) / 1_024
            return ContentCorpusBeat(offset: offset, gap: coin())
        }
    }
}


extension ContentBuilderRandomRecords {
    /// A random variant of a corpus Observation the reverse projection reads: its code, effective time, value and
    /// envelope statements each changed or not, independently. An Observation whose measurement is a Period one keeps
    /// a Period or loses it, and a code moves only to another instant measurement's, so no variant asks HealthKit to
    /// create a sample it raises on.
    static func variant(of observation: ContentCorpusJSON, using generator: inout HealthKitEffectiveTimeTests.SeededGenerator) throws -> Observation {
        var resource = try JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any] ?? [:]
        func happens() -> Bool {
            Int.random(in: 0..<4, using: &generator) == 0
        }
        let instant = resource["effectiveDateTime"] != nil
        if happens() {
            let unknown = ["http://loinc.org", "0000-0"]
            let codes = MeasurementCatalog.all.filter { $0.effective != .period }.map { [$0.code.system, $0.code.code] } + [unknown]
            let code = codes[Int.random(in: codes.indices, using: &generator)]
            resource["code"] = instant || code == unknown ? ["coding": [["system": code[0], "code": code[1]]]] : resource["code"]
        }
        if happens() {
            let instants = [
                "2026-08-17T15:30:00-07:00", "1999-12-31T23:59:59.999+05:45", "2026-08-17T22:30:00Z", "2026-08-17", "1600-02-29T12:00:00Z"
            ]
            resource["effectiveDateTime"] = instant ? instants.randomElement(using: &generator) : nil
        }
        if happens(), var quantity = resource["valueQuantity"] as? [String: Any] {
            quantity["value"] = Double(Int.random(in: 0...500_000, using: &generator)) / 1_000
            quantity["code"] = happens() ? "%" : quantity["code"]
            quantity["system"] = happens() ? "https://example.org/units" : quantity["system"]
            resource["valueQuantity"] = happens() ? nil : quantity
        }
        if happens(), var components = resource["component"] as? [Any], !components.isEmpty {
            components.remove(at: Int.random(in: components.indices, using: &generator))
            resource["component"] = components
        }
        if happens() {
            resource["status"] = "amended"
            resource["extension"] = [["url": Canonicals.writerRecordVersion.value?.url.absoluteString ?? "", "valueString": "5"]]
        }
        return try JSONDecoder().decode(Observation.self, from: JSONSerialization.data(withJSONObject: resource))
    }
}

#endif
