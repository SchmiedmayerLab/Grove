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
/// builds the corpus's: Observation samples of every plan, ECG records and every document record.
///
/// Every fault (a zone, an interval, an instant, a value, a metadata value; for an ECG, each of its checks) is drawn
/// independently, so a refused record usually states several faults, and which one each builder reports pins the
/// order its checks run in. Only values HealthKit can hold are drawn: a valence inside -1...1, years before 4000
/// wherever a sample is created from one.
struct ContentBuilderRandomRecords {
    /// How many records a run draws.
    static let count = 4_000

    /// Every Observation plan, with its source type.
    private static let observations: [(type: HealthKitSourceType, plan: ObservationPlan)] = HealthKitContentPlan.all.compactMap { plan in
        guard case .observation(let observation) = plan.route else {
            return nil
        }
        return (plan.sourceType, observation)
    }

    /// Every clinical record type.
    private static let clinicalTypes = HealthKitContentPlan.all.map(\.sourceType.rawValue).filter { $0.hasPrefix("HKClinicalTypeIdentifier") }

    /// Zones a sample may name, and names that are no zone.
    private static let zones: [ContentCorpusMetadataValue] = ["America/Los_Angeles", "Asia/Kolkata", "Asia/Kathmandu", "America/St_Johns", "UTC"]
        .map(ContentCorpusMetadataValue.string)
    /// Zone metadata no conversion admits.
    private static let invalidZones: [ContentCorpusMetadataValue] = [.string("Not/A-Time-Zone"), .integer(3)]
    /// The values of each metadata key an Observation component reads that its component admits, and some it does not.
    private static let componentMetadata: KeyValuePairs<String, (valid: [ContentCorpusMetadataValue], invalid: [ContentCorpusMetadataValue])> = [
        HKMetadataKeyHeartRateMotionContext: ([.integer(0), .integer(1), .integer(2)], [.integer(7), .string("active")]),
        HKMetadataKeyInsulinDeliveryReason: ([.integer(1), .integer(2)], [.integer(9), .string("bolus")]),
        HKMetadataKeyMenstrualCycleStart: ([.boolean(true), .boolean(false)], [.integer(2), .string("yes")])
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

    /// A start between 2000 and 2030, or, as a fault, in the year 10000, which no FHIR date-time states.
    private mutating func start() -> Double {
        guard fault(oneIn: 12) else {
            return Double.random(in: 946_684_800...1_893_456_000, using: &generator)
        }
        return 253_402_300_800 + Double(Int.random(in: 0..<86_400, using: &generator))
    }

    /// An ECG's start between 2000 and 2030 in a zone it names, or, as a fault, late on 9999-12-31 in UTC, so its
    /// voltages, or only its end, fall into the year 10000.
    private mutating func electrocardiogramStart(_ source: inout ContentCorpusSource) {
        guard fault(oneIn: 8) else {
            source.start = Double.random(in: 946_684_800...1_893_456_000, using: &generator)
            source.metadata[HKMetadataKeyTimeZone] = pick(Self.zones)
            return
        }
        source.start = pick([253_402_300_799.9, 253_402_300_770])
        source.metadata[HKMetadataKeyTimeZone] = .string("UTC")
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
    /// A sample of a random Observation plan: its value drawn for its value rule, its interval for its effective
    /// rule, and every metadata key a component reads, valid or not.
    private mutating func observationRecord() -> ContentCorpusSource {
        let (type, plan) = pick(Self.observations)
        let start = start()
        var end = start
        if case let .interval(nonZero) = plan.effective {
            end += fault() ? pick(nonZero ? [0, -30] : [-30]) : 60
        }
        var metadata: [String: ContentCorpusMetadataValue] = [:]
        metadata[HKMetadataKeyTimeZone] = zone()
        for (key, values) in Self.componentMetadata {
            let read = plan.metadataComponent?.field.key == key
            metadata[key] = read && fault() ? pick(values.invalid) : (read || coin() ? pick(values.valid) : nil)
        }
        metadata[HKMetadataKeyWasUserEntered] = coin() ? .boolean(coin()) : nil
        let record = value(of: type, plan.value, metadata: &metadata)
        return ContentCorpusSource(record: record, start: start, end: end, metadata: metadata, device: nil, writer: .unattributed, context: .plain)
    }

    /// A record of `type` whose value is drawn for `rule`: inside its domain, or, as a fault, outside it.
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
            let raw = fault() || valid.isEmpty ? pick(unresolved.sorted() + [-1, 9, 99]) : pick(valid)
            return .category(type: type.rawValue, value: raw)
        case .duration:
            return .category(type: type.rawValue, value: fault() ? 1 : 0)
        case .protection:
            let key = HKMetadataKeySexualActivityProtectionUsed
            metadata[key] = fault() ? .string("yes") : pick([.boolean(true), .boolean(false), nil])
            return .category(type: type.rawValue, value: fault() ? 2 : 0)
        case .bloodPressure:
            return bloodPressure()
        case .workout:
            return workout()
        case .stateOfMind:
            let labels = (0..<Int.random(in: 0...4, using: &generator)).map { _ in pick(Array(0...41) + [999]) }
            let associations = (0..<Int.random(in: 0...4, using: &generator)).map { _ in pick(Array(0...21) + [999]) }
            let valence = (Double.random(in: -1...1, using: &generator) * 100).rounded() / 100
            return .stateOfMind(kind: pick([0, 1, 2, 99]), valence: valence, labels: labels, associations: associations)
        }
    }

    /// A quantity of `type` read as `read`: a value inside the template's domain, or, as a fault, a non-finite, huge
    /// or out-of-domain one.
    private mutating func quantity(of type: HealthKitSourceType, template: QuantityTemplate, read: QuantityRead) -> ContentCorpusRecord {
        let domain = template.domain
        let low = domain.map { NSDecimalNumber(decimal: $0.minimum.value).doubleValue } ?? 0
        let high = domain?.maximum.map { NSDecimalNumber(decimal: $0.value).doubleValue } ?? low + 1_000
        var value = Double.random(in: low...high, using: &generator)
        value = domain?.integerOnly == true ? value.rounded() : (value * 1_000).rounded() / 1_000
        if fault() {
            value = pick([.nan, .infinity, -.infinity, 1e300, low - 1, high + 1, low + 0.5])
        }
        switch read {
        case .unit(let unit):
            return .quantity(type: type.rawValue, value: value, unit: unit.unitString)
        case .percent:
            return .quantity(type: type.rawValue, value: value / 100, unit: "%")
        case .score:
            return .assessment(type: type.rawValue, score: Int(exactly: value.rounded()) ?? -1)
        }
    }

    /// A blood-pressure correlation of both members, or, as faults, one missing or one reading no contract admits.
    private mutating func bloodPressure() -> ContentCorpusRecord {
        var members = [
            ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue, value: pick([120, 135.5, 90])),
            ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue, value: pick([80, 70, 95]))
        ]
        if fault() {
            members[Int.random(in: 0...1, using: &generator)].value = pick([.nan, -1, 1e21])
        }
        if fault() {
            members.remove(at: Int.random(in: 0...1, using: &generator))
        }
        return .correlation(type: HKCorrelationTypeIdentifier.bloodPressure.rawValue, members: members.shuffled(using: &generator))
    }

    /// A workout of any activity, with any statistics, its duration or one statistic, as a fault, not a reading.
    private mutating func workout() -> ContentCorpusRecord {
        var statistics = Self.workoutStatistics.filter { _ in coin() }
        if fault(), !statistics.isEmpty {
            let index = Int.random(in: statistics.indices, using: &generator)
            statistics[index].sum = statistics[index].sum.map { _ in .nan }
            statistics[index].average = statistics[index].average.map { _ in -1 }
        }
        let duration = fault() ? pick([.nan, -1]) : Double.random(in: 0...7_200, using: &generator).rounded()
        return .workout(activity: pick(Array(0...90) + [3_000, 9_999]), duration: duration, statistics: statistics)
    }
}


extension ContentBuilderRandomRecords {
    /// An ECG record from the corpus's sinus-rhythm reading, each of its checks drawn to fail on its own.
    private mutating func electrocardiogramRecord() -> ContentCorpusSource {
        var reading = ContentCorpusGrid.electrocardiogramReading
        var source = ContentCorpusGrid.electrocardiogramSource(reading)
        electrocardiogramStart(&source)
        source.end = source.start + (fault(oneIn: 8) ? -30 : 30)
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

    /// Symptoms as the status states them, or, as faults, an unknown status, a mismatch, a type the ECG does not
    /// admit, or one sample twice.
    private mutating func symptoms(of reading: inout ContentCorpusElectrocardiogram) {
        let admitted = [HKCategoryTypeIdentifier.chestTightnessOrPain, .fatigue, .dizziness].map(\.rawValue)
        let present = HKElectrocardiogram.SymptomsStatus.present.rawValue
        reading.symptomsStatus = fault(oneIn: 10) ? 99 : pick([0, 1, present])
        let stated = reading.symptomsStatus == present ? Int.random(in: 1...2, using: &generator) : 0
        reading.symptoms = (0..<stated).map { ordinal in
            ContentCorpusElectrocardiogram.Symptom(type: pick(admitted), value: 2, ordinal: 0xE1 + UInt8(ordinal))
        }
        if fault(oneIn: 10) {
            reading.symptoms.append(ContentCorpusElectrocardiogram.Symptom(type: HKCategoryTypeIdentifier.headache.rawValue, value: 2, ordinal: 0xE8))
        }
        if fault(oneIn: 10), let first = reading.symptoms.first {
            reading.symptoms.append(first)
        }
        if fault(oneIn: 10) {
            reading.symptomsStatus = reading.symptoms.isEmpty ? present : 1
        }
    }

    /// A heartbeat series, a route, a clinical record or a CDA document, each refused, as a fault, for an empty
    /// series, a reading the column schema cannot write, a release or payload not admitted, or no bytes.
    private mutating func documentRecord() -> ContentCorpusSource {
        let record: ContentCorpusRecord
        switch Int.random(in: 0..<4, using: &generator) {
        case 0:
            var beats = fault(oneIn: 6) ? [] : ContentCorpusGrid.heartbeats.filter { _ in coin() || coin() }
            if fault(oneIn: 6), !beats.isEmpty {
                beats[0].offset = .nan
            }
            record = .heartbeatSeries(beats: beats)
        case 1:
            var locations = fault(oneIn: 6) ? [] : ContentCorpusGrid.routeLocations.filter { _ in coin() || coin() }
            if fault(oneIn: 6), !locations.isEmpty {
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
        return ContentCorpusSource(record, end: ContentCorpusGrid.start + 60, metadata: zone().map { [HKMetadataKeyTimeZone: $0] } ?? [:])
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
