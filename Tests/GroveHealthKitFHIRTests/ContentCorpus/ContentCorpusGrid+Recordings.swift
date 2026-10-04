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
import HealthKit


/// ECG evidence, precedence and time edges, heartbeat series and workout routes.
extension ContentCorpusGrid {
    /// A fix at rest facing due north, every reading that can be unavailable exactly zero: a zero is a reading, so the
    /// track writes it, unlike the negative values CoreLocation reports for an unavailable one.
    static let restingFix = ContentCorpusLocation(
        offset: 2,
        latitude: 37.4276,
        longitude: -122.1698,
        altitude: 0,
        horizontalAccuracy: 5,
        verticalAccuracy: 0,
        course: 0,
        courseAccuracy: 0,
        speed: 0,
        speedAccuracy: 0
    )

    /// The conformance fixtures' sinus-rhythm reading: four voltages 2 ms apart at 500 Hz, 72 bpm, no symptoms.
    static let electrocardiogramReading = ContentCorpusElectrocardiogram(
        classification: HKElectrocardiogram.Classification.sinusRhythm.rawValue,
        symptomsStatus: HKElectrocardiogram.SymptomsStatus.none.rawValue,
        reportedCount: 4,
        averageHeartRate: 72,
        samplingFrequency: 500,
        voltages: [(0.25, 0.125), (0.252, 0.25), (0.254, -0.125), (0.256, 0)].map { ContentCorpusElectrocardiogram.Voltage(offset: $0, millivolts: $1) }
    )

    /// The zone and algorithm version an Apple Watch ECG states.
    static let electrocardiogramMetadata = zone.merging([HKMetadataKeyAppleECGAlgorithmVersion: .integer(2)]) { _, new in new }

    /// Three beats, the last after a gap.
    static let heartbeats = [
        ContentCorpusBeat(offset: 0, gap: false), ContentCorpusBeat(offset: 0.84, gap: false), ContentCorpusBeat(offset: 1.71, gap: true)
    ]

    /// The goldens' two fixes one second apart; the second reports no vertical accuracy, course or speed.
    static let routeLocations = [
        ContentCorpusLocation(
            offset: 0,
            latitude: 37.4275,
            longitude: -122.1697,
            altitude: 30.5,
            horizontalAccuracy: 5,
            verticalAccuracy: 3,
            course: 91.5,
            courseAccuracy: 10,
            speed: 2.25,
            speedAccuracy: 0.5
        ),
        ContentCorpusLocation(
            offset: 1,
            latitude: 37.4276,
            longitude: -122.1698,
            altitude: 0,
            horizontalAccuracy: 65,
            verticalAccuracy: -1,
            course: -1,
            courseAccuracy: -1,
            speed: -1,
            speedAccuracy: -1
        )
    ]

    /// Every classification, symptoms status and algorithm version, average heart rate and sampling frequency
    /// edges, every waveform refusal, zones, symptom relationships, and the plain sample entry point.
    static var electrocardiograms: [ContentCorpusVector] {
        let averages: [(String, Double?)] = [("none", nil), ("fraction", 72.5), ("nan", .nan), ("zero", 0), ("tiny", 1e-7)]
        let frequencies: [(String, Double?)] = [("none", nil), ("mismatch", 250), ("zero", 0), ("nan", .nan), ("negative", -500), ("near", 499.99)]
        let readings: [(String, ContentCorpusElectrocardiogram)] = [("row", electrocardiogramReading)]
            + [0, 2, 3, 4, 5, 6, 100, 99].map { raw in ("classification/\(raw)", reading { $0.classification = raw }) }
            + [0, 99].map { status in ("symptoms-status/\(status)", reading { $0.symptomsStatus = status }) }
            + averages.map { label, rate in ("average-heart-rate/\(label)", reading { $0.averageHeartRate = rate }) }
            + frequencies.map { label, rate in ("sampling-frequency/\(label)", reading { $0.samplingFrequency = rate }) }
            + waveformEdges
            + symptomRelationships
        return readings.map { label, reading in electrocardiogram(label, reading) } + electrocardiogramFacts
            + electrocardiogramPrecedence + electrocardiogramTimes
    }

    /// Two faults at once for every pair of adjacent checks of an ECG conversion (zone, lead presence, count,
    /// offsets, period, sampling frequency, finite voltages, symptom contexts, symptom validation and status,
    /// source period, classification, algorithm version, average heart rate, then the ECG's source facts): which one
    /// is reported pins their order.
    static var electrocardiogramPrecedence: [ContentCorpusVector] {
        let present = HKElectrocardiogram.SymptomsStatus.present.rawValue
        let chest = ContentCorpusElectrocardiogram.Symptom(type: HKCategoryTypeIdentifier.chestTightnessOrPain.rawValue, value: 2, ordinal: 0xE1)
        let headache = ContentCorpusElectrocardiogram.Symptom(type: HKCategoryTypeIdentifier.headache.rawValue, value: 2, ordinal: 0xE1)
        let versionThree = zone.merging([HKMetadataKeyAppleECGAlgorithmVersion: .integer(3)]) { $1 }
        func source(
            _ reading: ContentCorpusElectrocardiogram,
            metadata: [String: ContentCorpusMetadataValue] = electrocardiogramMetadata,
            reversed: Bool = false
        ) -> ContentCorpusSource {
            var source = electrocardiogramSource(reading)
            source.metadata = metadata
            source.end = reversed ? start - 30 : source.end
            return source
        }
        // Its voltages fall on 9999-12-31, its end into the year 10000.
        var sourcePeriodInYear10000 = source(reading { $0.classification = 99 }, metadata: [HKMetadataKeyTimeZone: .string("UTC")])
        sourcePeriodInYear10000.start = 253_402_300_770
        sourcePeriodInYear10000.end = 253_402_300_800
        let missingLead = reading { $0.voltages[2].millivolts = nil }
        let nanVoltage = reading { $0.voltages[1].millivolts = .nan }
        let nonUniform = reading { $0.voltages[2].offset = 0.255 }
        let pairs: [(String, ContentCorpusSource)] = [
            ("zone-before-missing-lead", source(missingLead, metadata: electrocardiogramMetadata.merging([HKMetadataKeyTimeZone: .string("Not/A-Time-Zone")]) { $1 })),
            ("missing-lead-before-count", source(reading(missingLead) { $0.reportedCount = 3 })),
            ("count-before-offsets", source(reading(reading { $0.reportedCount = 3 }) { $0.voltages[0].offset = -0.002 })),
            ("offsets-before-period", source(reading(nonUniform) { $0.voltages[3].offset = -1 })),
            ("period-before-frequency", source(reading(nonUniform) { $0.samplingFrequency = 250 })),
            ("frequency-before-voltages", source(reading(nanVoltage) { $0.samplingFrequency = 250 })),
            ("voltages-before-symptom-contexts", source(reading(symptoms(present, [chest])) { reading in
                reading.voltages[1].millivolts = .nan
                reading.symptomContexts = 0
            })),
            ("symptom-contexts-before-symptom-validation", source(reading(symptoms(present, [headache])) { $0.symptomContexts = 0 })),
            ("symptom-validation-before-source-period", source(symptoms(present, [headache]), reversed: true)),
            ("symptoms-status-before-source-period", source(reading { $0.symptomsStatus = 99 }, reversed: true)),
            ("symptoms-status-before-classification", source(reading(reading { $0.symptomsStatus = 99 }) { $0.classification = 99 })),
            ("source-period-before-classification", sourcePeriodInYear10000),
            ("classification-before-algorithm-version", source(reading { $0.classification = 99 }, metadata: versionThree)),
            ("algorithm-version-before-average-heart-rate", source(reading { $0.averageHeartRate = .nan }, metadata: versionThree)),
            ("average-heart-rate-before-sync", source(reading { $0.averageHeartRate = .nan }, metadata: electrocardiogramMetadata.merging(brokenSync) { $1 }))
        ]
        return pairs.map { label, source in
            convert("electrocardiogram/precedence/\(label)", source)
        }
    }

    /// The base ECG at instants its exact timing has to carry: a start a quarter second before a minute, so the
    /// first voltage falls into the next one; a local year past 9999; 1500 in Los Angeles (local mean time) and in
    /// UTC; and both occurrences of Los Angeles's repeated 2026 hour.
    static var electrocardiogramTimes: [ContentCorpusVector] {
        func at(_ instant: Double, metadata: [String: ContentCorpusMetadataValue] = electrocardiogramMetadata) -> ContentCorpusSource {
            var source = electrocardiogramSource(electrocardiogramReading)
            source.start = instant
            source.end = instant + 30
            source.metadata = metadata
            return source
        }
        let utc: [String: ContentCorpusMetadataValue] = [HKMetadataKeyTimeZone: .string("UTC"), HKMetadataKeyAppleECGAlgorithmVersion: .integer(2)]
        let instants: [(String, ContentCorpusSource)] = [
            ("start-carries-into-minute", at(1_787_005_859.75)),
            ("year-10000", at(253_402_329_600)),
            ("pre-reform-1500", at(-14_831_769_600)),
            ("pre-reform-1500/utc", at(-14_831_769_600, metadata: utc)),
            ("repeated-hour-first", at(1_793_521_800)),
            ("repeated-hour-second", at(1_793_525_400))
        ]
        return instants.map { label, source in
            convert("electrocardiogram/time/\(label)", source)
        }
    }

    /// Correlated symptoms: one, several sorted by type and UUID, refused types and duplicates, a status that
    /// contradicts them, an invalid symptom value, a missing context, and what fails first beside them (each symptom
    /// is checked for its type, then for its sample, before the next one).
    static var symptomRelationships: [(String, ContentCorpusElectrocardiogram)] {
        let present = HKElectrocardiogram.SymptomsStatus.present.rawValue
        let chest = HKCategoryTypeIdentifier.chestTightnessOrPain.rawValue
        let fatigue = HKCategoryTypeIdentifier.fatigue.rawValue
        let headache = HKCategoryTypeIdentifier.headache.rawValue
        func symptom(_ type: String, _ value: Int, _ ordinal: UInt8) -> ContentCorpusElectrocardiogram.Symptom {
            ContentCorpusElectrocardiogram.Symptom(type: type, value: value, ordinal: ordinal)
        }
        return [
            ("symptoms/one", symptoms(present, [symptom(chest, 2, 0xE1)])),
            ("symptoms/two-types", symptoms(present, [symptom(fatigue, 2, 0xE2), symptom(chest, 3, 0xE1)])),
            ("symptoms/same-type", symptoms(present, [symptom(chest, 2, 0xE4), symptom(chest, 4, 0xE3)])),
            ("symptoms/unsupported-type", symptoms(present, [symptom(headache, 2, 0xE1)])),
            ("symptoms/duplicate-source", symptoms(present, [symptom(chest, 2, 0xE1), symptom(fatigue, 2, 0xE1)])),
            ("symptoms/unexpected", symptoms(HKElectrocardiogram.SymptomsStatus.none.rawValue, [symptom(chest, 2, 0xE1)])),
            ("symptoms/required", symptoms(present, [])),
            ("symptoms/invalid-value", symptoms(present, [symptom(chest, 9, 0xE1)])),
            ("symptoms/context-missing", reading(symptoms(present, [symptom(chest, 2, 0xE1)])) { $0.symptomContexts = 0 }),
            ("precedence/symptoms-before-classification", reading(symptoms(present, [symptom(headache, 2, 0xE1)])) { $0.classification = 99 }),
            ("precedence/duplicate-source-before-later-type", symptoms(present, [symptom(chest, 2, 0xE1), symptom(chest, 2, 0xE1), symptom(headache, 2, 0xE2)])),
            ("precedence/type-before-duplicate-source", symptoms(present, [symptom(chest, 2, 0xE1), symptom(headache, 2, 0xE1)])),
            ("precedence/count-before-average-heart-rate", reading { reading in
                reading.reportedCount = 3
                reading.averageHeartRate = .nan
            })
        ]
    }

    /// Waveform refusals: counts, offsets, voltages and lead presence.
    static var waveformEdges: [(String, ContentCorpusElectrocardiogram)] {
        func offsets(_ values: [Double]) -> ContentCorpusElectrocardiogram {
            reading { reading in
                reading.voltages = zip(values, reading.voltages).map { offset, voltage in
                    ContentCorpusElectrocardiogram.Voltage(offset: offset, millivolts: voltage.millivolts)
                }
            }
        }
        func voltage(at index: Int, _ millivolts: Double?) -> ContentCorpusElectrocardiogram {
            reading { $0.voltages[index].millivolts = millivolts }
        }
        return [
            ("count/zero", reading { $0.reportedCount = 0 }),
            ("count/mismatch", reading { $0.reportedCount = 3 }),
            ("count/one", reading { reading in
                reading.reportedCount = 1
                reading.voltages = Array(reading.voltages.prefix(1))
            }),
            ("offsets/negative", offsets([-0.002, 0, 0.002, 0.004])),
            ("offsets/repeated", offsets([0.25, 0.25, 0.252, 0.254])),
            ("offsets/non-uniform", offsets([0.25, 0.252, 0.255, 0.256])),
            ("offsets/nan", offsets([0.25, .nan, 0.254, 0.256])),
            ("voltages/nan", voltage(at: 1, .nan)),
            ("voltages/missing-lead", voltage(at: 2, nil)),
            ("voltages/tiny", voltage(at: 1, 1e-7)),
            ("voltages/huge", voltage(at: 1, 1e21))
        ]
    }

    /// The ECG's own facts: zones, algorithm versions, manual entry, a reversed interval, every link, and the
    /// plain sample entry point, which has no voltages to convert.
    static var electrocardiogramFacts: [ContentCorpusVector] {
        let version = HKMetadataKeyAppleECGAlgorithmVersion
        let metadata: [(String, [String: ContentCorpusMetadataValue])] = [
            ("zone/none", [version: .integer(2)]),
            ("zone/invalid", [HKMetadataKeyTimeZone: .string("Not/A-Time-Zone"), version: .integer(2)]),
            ("zone/kathmandu", [HKMetadataKeyTimeZone: .string("Asia/Kathmandu"), version: .integer(2)]),
            ("algorithm-version/absent", zone), ("algorithm-version/1", zone.merging([version: .integer(1)]) { $1 }),
            ("algorithm-version/3", zone.merging([version: .integer(3)]) { $1 }),
            ("algorithm-version/string", zone.merging([version: .string("2")]) { $1 }),
            ("algorithm-version/double", zone.merging([version: .double(2)]) { $1 }),
            ("user-entered", electrocardiogramMetadata.merging([HKMetadataKeyWasUserEntered: .boolean(true)]) { $1 })
        ]
        var reversed = electrocardiogramSource(electrocardiogramReading)
        reversed.end = start - 30
        var linked = electrocardiogramSource(electrocardiogramReading)
        linked.device = .watch
        linked.context = .linked
        linked.metadata[HKMetadataKeyWasUserEntered] = .boolean(true)
        var zoneFirst = electrocardiogramSource(reading { $0.reportedCount = 3 })
        zoneFirst.metadata[HKMetadataKeyTimeZone] = .string("Not/A-Time-Zone")
        return metadata.map { label, metadata in
            var source = electrocardiogramSource(electrocardiogramReading)
            source.metadata = metadata
            return convert("electrocardiogram/\(label)", source)
        } + [
            convert("electrocardiogram/reversed", reversed),
            convert("electrocardiogram/linked", linked),
            convert("electrocardiogram/precedence/zone-before-count", zoneFirst),
            convert(
                "electrocardiogram/sample-entry",
                ContentCorpusSource(.bare(type: HKObjectType.electrocardiogramType().identifier, sampleClass: "HKElectrocardiogram"), end: start + 30)
            )
        ]
    }

    /// Heartbeat series and workout routes: their payloads, empty series, every link, the plain sample entry point, and
    /// a route's disclosure and track checked before its source facts.
    static var recordings: [ContentCorpusVector] {
        func series(_ label: String, _ beats: [ContentCorpusBeat], metadata: [String: ContentCorpusMetadataValue] = zone) -> ContentCorpusVector {
            convert("heartbeat-series/\(label)", ContentCorpusSource(.heartbeatSeries(beats: beats), end: start + 2, metadata: metadata))
        }
        func route(
            _ label: String,
            _ locations: [ContentCorpusLocation],
            disclosed: Bool = true,
            metadata: [String: ContentCorpusMetadataValue] = zone
        ) -> ContentCorpusVector {
            convert("workout-route/\(label)", ContentCorpusSource(.workoutRoute(locations: locations, disclosed: disclosed), end: start + 1, metadata: metadata))
        }
        let unavailable = routeLocations.map { fix in
            var fix = fix
            fix.verticalAccuracy = -1
            fix.course = -1
            fix.courseAccuracy = -1
            fix.speed = -1
            fix.speedAccuracy = -1
            return fix
        }
        var linkedSeries = ContentCorpusSource(.heartbeatSeries(beats: heartbeats), end: start + 2)
        var linkedRoute = ContentCorpusSource(.workoutRoute(locations: routeLocations, disclosed: true), end: start + 1)
        linkedSeries.device = .watch
        linkedSeries.context = .linked
        linkedRoute.device = .watch
        linkedRoute.context = .linked
        return [
            series("row", heartbeats), series("empty", []), series("single", [heartbeats[0]]),
            series("fractional", [ContentCorpusBeat(offset: 0.1 + 0.2, gap: false), ContentCorpusBeat(offset: 1e-7, gap: true)]),
            series("late", [ContentCorpusBeat(offset: 86_400.5, gap: false)]),
            series("sub-millisecond", [ContentCorpusBeat(offset: 0.853515625, gap: false)]),
            series("zone-invalid", heartbeats, metadata: [HKMetadataKeyTimeZone: .string("Not/A-Time-Zone")]),
            convert("heartbeat-series/linked", linkedSeries),
            convert("heartbeat-series/sample-entry", ContentCorpusSource(.bare(type: HKSeriesType.heartbeat().identifier, sampleClass: "HKHeartbeatSeriesSample"))),
            route("row", routeLocations), route("omitted", routeLocations, disclosed: false), route("empty", []),
            route("unavailable-readings", unavailable),
            route("zero-readings", [routeLocations[0], restingFix]),
            convert("workout-route/linked", linkedRoute),
            convert("workout-route/sample-entry", ContentCorpusSource(.bare(type: HKSeriesType.workoutRoute().identifier, sampleClass: "HKWorkoutRoute"))),
            route("precedence/omission-before-sync", routeLocations, disclosed: false, metadata: brokenSync),
            route("precedence/empty-before-sync", [], metadata: brokenSync)
        ]
    }

    /// The base reading with one change.
    static func reading(
        _ base: ContentCorpusElectrocardiogram = electrocardiogramReading,
        _ change: (inout ContentCorpusElectrocardiogram) -> Void
    ) -> ContentCorpusElectrocardiogram {
        var reading = base
        change(&reading)
        return reading
    }

    /// The base reading under `status`, with `samples` correlated.
    static func symptoms(_ status: Int, _ samples: [ContentCorpusElectrocardiogram.Symptom]) -> ContentCorpusElectrocardiogram {
        reading { reading in
            reading.symptomsStatus = status
            reading.symptoms = samples
        }
    }

    /// A 30-second ECG at the base instant stating `reading`, with the zone and algorithm version a watch states.
    static func electrocardiogramSource(_ reading: ContentCorpusElectrocardiogram) -> ContentCorpusSource {
        ContentCorpusSource(.electrocardiogram(reading: reading), end: start + 30, metadata: electrocardiogramMetadata)
    }

    /// The vector converting the base ECG with `reading`, under `electrocardiogram/<label>`.
    static func electrocardiogram(_ label: String, _ reading: ContentCorpusElectrocardiogram) -> ContentCorpusVector {
        convert("electrocardiogram/\(label)", electrocardiogramSource(reading))
    }
}

#endif
