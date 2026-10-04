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


/// The content plans' builders against today's builders (oracle O4): every content-corpus record, and seeded random
/// records whose faults are drawn independently so most refused ones state several, builds to the same JSON tokens or
/// is refused with the same error by both; every corpus Observation and seeded random variant of one projects back to
/// the same sample, or is refused the same way, by both reverse projections.
///
/// Temporary: it reads the old content internals, so the old code's deletion (M6) deletes it; the goldens and the
/// content corpus then pin the plans' output.
@Suite
struct ContentBuilderDifferentialTests {
    /// The corpus splits into this many shards, which run in parallel.
    static let shards = 8

    /// The plans' reverse projection.
    private static let plannedProjection: ContentCorpusRecorder.Projection = { observation throws(HealthKitSampleProjectionError) in
        try HealthKitSampleProjection.sample(of: observation, syncIdentifier: nil)
    }

    /// Compares both builders on one shard of the corpus: every record a builder runs for, every reverse projection
    /// and every round trip. A record this platform cannot rebuild is skipped, as the corpus skips it.
    @Test(arguments: 0..<shards)
    func everyCorpusRecordBuildsAsToday(shard: Int) throws {
        var differences: [String] = []
        var compared = 0
        let vectors = try ContentCorpusStore.vectors(in: ContentCorpusStore.checkedIn())
        for (index, vector) in vectors.enumerated() where index % Self.shards == shard {
            try autoreleasepool {
                guard let outcomes = try Self.outcomes(of: vector.input) else {
                    return
                }
                compared += 1
                if let difference = Self.difference(outcomes.today, outcomes.planned) {
                    differences.append("\(vector.id): \(difference)")
                }
            }
        }
        #expect(compared > 300, "shard \(shard) compares only \(compared) vectors")
        #expect(differences.isEmpty, "\(differences.count) corpus vectors build differently: \(differences.prefix(10))")
    }

    @Test("Seeded random records, most with several faults, build as today's builders build them or refuse them alike")
    func seededRandomRecordsBuildAsToday() throws {
        var records = ContentBuilderRandomRecords(seed: 0x4F34_2D42_7569_6C64)
        var differences: [String] = []
        var refusedWithSeveralFaults = 0
        var compared = 0
        for index in 0..<ContentBuilderRandomRecords.count {
            try autoreleasepool {
                let (source, faults) = records.next()
                guard let outcomes = try Self.outcomes(of: .convert(source: source)) else {
                    return
                }
                compared += 1
                if let difference = Self.difference(outcomes.today, outcomes.planned) {
                    differences.append("record \(index) (\(try ContentCorpusStore.inputText(.convert(source: source)))): \(difference)")
                } else if outcomes.today.isRefusal, faults > 1 {
                    refusedWithSeveralFaults += 1
                }
            }
        }
        #expect(compared > ContentBuilderRandomRecords.count * 9 / 10, "only \(compared) random records reach a builder")
        #expect(refusedWithSeveralFaults > ContentBuilderRandomRecords.count / 6, "only \(refusedWithSeveralFaults) multi-fault refusals")
        #expect(differences.isEmpty, "\(differences.count) random records build differently: \(differences.prefix(5))")
    }

    @Test("Seeded random variants of every corpus Observation project back as today's reverse projection does")
    func seededRandomObservationsProjectAsToday() throws {
        var generator = HealthKitEffectiveTimeTests.SeededGenerator(state: 0x4F34_2D52_6576_6572)
        let observations = try ContentCorpusStore.vectors(in: ContentCorpusStore.checkedIn()).compactMap { vector -> ContentCorpusJSON? in
            guard case .reverse(let observation) = vector.input else {
                return nil
            }
            return observation
        }
        try #require(!observations.isEmpty)
        var differences: [String] = []
        for index in 0..<1_500 {
            try autoreleasepool {
                let variant = try ContentBuilderRandomRecords.variant(of: observations[index % observations.count], using: &generator)
                let today = ContentCorpusRecorder.reverse(variant)
                let planned = ContentCorpusRecorder.reverse(variant, projection: Self.plannedProjection)
                if let difference = TokenDiff.firstDifference(expected: today, actual: planned) {
                    differences.append("variant \(index): \(difference)")
                }
            }
        }
        #expect(differences.isEmpty, "\(differences.count) Observations project differently: \(differences.prefix(5))")
    }
}


extension ContentBuilderDifferentialTests {
    /// Both sides' outcomes for one corpus input, or `nil` when no builder or projection runs for it here.
    private static func outcomes(of input: ContentCorpusInput) throws -> ContentBuilderPair.Outcomes? {
        do {
            switch input {
            case .convert(let source):
                return try ContentBuilderPair.outcomes(of: source)
            case .roundTrip(let source):
                let builders = try ContentBuilderPair.outcomes(of: source)
                let today = ContentBuilderOutcome {
                    .object(["record": builders?.today.tokens ?? .null, "roundTrip": try ContentCorpusRecorder.roundTrip(source)])
                }
                let planned = ContentBuilderOutcome {
                    let roundTrip = try ContentCorpusRecorder.roundTrip(source, projection: plannedProjection)
                    return .object(["record": builders?.planned.tokens ?? .null, "roundTrip": roundTrip])
                }
                return (today, planned)
            case .reverse(let observation):
                let decoded = try observation.decoded(as: Observation.self)
                let today = ContentCorpusRecorder.reverse(decoded)
                return (.built(today), .built(ContentCorpusRecorder.reverse(decoded, projection: plannedProjection)))
            case .retract, .catalog:
                return nil
            }
        } catch ContentCorpusSamples.RebuildError.unavailableHere {
            return nil
        }
    }

    /// How two outcomes differ, or `nil` when they are equal.
    private static func difference(_ today: ContentBuilderOutcome, _ planned: ContentBuilderOutcome) -> String? {
        switch (today, planned) {
        case let (.built(expected), .built(actual)):
            TokenDiff.firstDifference(expected: expected, actual: actual)
        case let (.threw(expected), .threw(actual)):
            expected == actual ? nil : "today throws \(expected), the plans throw \(actual)"
        default:
            "today \(today), the plans \(planned)"
        }
    }
}

#endif
