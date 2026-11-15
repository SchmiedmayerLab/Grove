//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

import Foundation
@testable import GroveSensorKit
@testable import GroveSensorKitFHIR
import Testing


struct SensorKitSourceRecordIDSliceTests {
    private static let token = "SRSensor.accelerometer"
    private static let device = "Watch7,1"

    private static func coordinate(sequence: UInt64 = 7, streamPartition: UInt64 = 0x5EED) -> SensorKit.AcquisitionBatchCoordinate {
        SensorKit.AcquisitionBatchCoordinate(
            streamPartition: streamPartition,
            cursorTimestamp: Date(timeIntervalSinceReferenceDate: 12_345),
            resetGeneration: 2,
            sequence: sequence
        )
    }

    private static func slice(
        batch: SensorKit.AcquisitionBatchCoordinate = coordinate(),
        token: String = token,
        device: String = device,
        rows: Range<UInt64> = 0..<100
    ) throws -> SensorKitSourceRecordID {
        try SensorKitSourceRecordID.derivedSlice(acquisitionBatch: batch, sourceToken: token, deviceProductType: device, rows: rows)
    }

    @Test("The same batch, stream and rows reproduce the slice identity")
    func derivationIsDeterministic() throws {
        let first = try Self.slice()
        #expect(try Self.slice() == first)
        // A version-8 UUID, as every derived source record identity.
        let bytes = first.uuid.uuid
        #expect(bytes.6 >> 4 == 8 && bytes.8 >> 6 == 2)
    }

    @Test("Every input separates slice identities")
    func everyInputIsSignificant() throws {
        let variants = [
            try Self.slice(),
            try Self.slice(batch: Self.coordinate(sequence: 8)),
            try Self.slice(batch: Self.coordinate(streamPartition: 0x5EEE)),
            try Self.slice(token: "SRSensor.rotationRate"),
            try Self.slice(device: "iPhone17,1"),
            try Self.slice(rows: 1..<100),
            try Self.slice(rows: 0..<99),
            try Self.slice(rows: 100..<200)
        ]
        #expect(Set(variants).count == variants.count)
    }

    @Test("Adjacent fields and row bounds cannot be shifted into one another")
    func framingKeepsFieldsApart() throws {
        #expect(try Self.slice(token: "ab", device: "c") != Self.slice(token: "a", device: "bc"))
        #expect(try Self.slice(rows: 1..<123) != Self.slice(rows: 11..<23))
        #expect(try Self.slice(rows: 1..<123) != Self.slice(rows: 112..<113))
    }

    @Test("A slice never shares the identity of a whole record of its batch")
    func slicesAreDistinctFromRecordIdentities() throws {
        let batch = Self.coordinate()
        let records = (UInt64(0)..<100).map {
            SensorKitSourceRecordID.derived(acquisitionBatch: batch, sourceToken: Self.token, deviceProductType: Self.device, recordOrdinal: $0)
        }
        let slices = try [0..<1, 0..<100, 1..<2, 99..<100].map { try Self.slice(batch: batch, rows: $0) }
        #expect(Set(records).isDisjoint(with: slices))
        #expect(Set(slices).count == slices.count)
    }

    @Test("An empty row range has no identity")
    func emptyRangeIsRefused() {
        for rows in [UInt64(0)..<0, 5..<5, .max ..< .max] {
            #expect(throws: SensorKitSourceRecordID.SliceIdentityError.invalidRange) {
                try Self.slice(rows: rows)
            }
        }
    }
}

#endif
