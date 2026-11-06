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
import SensorKit
import Testing


struct SensorKitSourceRecordIDDerivationTests {
    @available(iOS 18, *)
    private var firstCoordinate: SensorKit.AcquisitionBatchCoordinate {
        SensorKit.AcquisitionBatchCoordinate(
            streamPartition: 0x5EED,
            cursorTimestamp: Date(timeIntervalSinceReferenceDate: 12_345),
            resetGeneration: 2,
            sequence: 7
        )
    }

    @Test("An exact anchored-delivery retry reproduces its source record identity")
    @available(iOS 18, *)
    func retryReproducesIdentity() {
        let first = derive(at: firstCoordinate, ordinal: 3)
        let retry = derive(at: firstCoordinate, ordinal: 3)

        #expect(first == retry)
        #expect(firstCoordinate.stableValue.hasPrefix("sensorkit-batch-v1:\(0x5EED):"))
    }

    @Test("Byte-identical records at distinct acquisition coordinates remain distinct")
    @available(iOS 18, *)
    func distinctCoordinatesRemainDistinct() {
        let nextCoordinate = SensorKit.AcquisitionBatchCoordinate(
            streamPartition: firstCoordinate.streamPartition,
            cursorTimestamp: firstCoordinate.cursorTimestamp,
            resetGeneration: firstCoordinate.resetGeneration,
            sequence: firstCoordinate.sequence + 1
        )

        #expect(derive(at: firstCoordinate, ordinal: 3) != derive(at: nextCoordinate, ordinal: 3))
    }

    @Test("Two fresh cursors, such as an installation and its reinstall, name disjoint source records")
    @available(iOS 18, *)
    func freshCursorsNameDisjointRecords() {
        func firstBatch() -> SensorKit.AcquisitionBatchCoordinate {
            QueryAnchor().preparing(.sampleCount(deliveryTimestamp: firstCoordinate.cursorTimestamp, sampleCount: 1)).acquisitionBatchCoordinate
        }
        let (installation, reinstall) = (firstBatch(), firstBatch())
        for ordinal: UInt64 in 0..<4 {
            #expect(derive(at: installation, ordinal: ordinal) != derive(at: reinstall, ordinal: ordinal))
        }
    }

    @Test("Record ordinal and cursor partitions are identity-bearing")
    @available(iOS 18, *)
    func ordinalAndPartitionsAreIdentityBearing() {
        let baseline = derive(at: firstCoordinate, ordinal: 3)

        #expect(baseline != derive(at: firstCoordinate, ordinal: 4))
        #expect(baseline != derive(at: firstCoordinate, sourceToken: "SRSensor.visits", ordinal: 3))
        #expect(baseline != derive(at: firstCoordinate, deviceProductType: "Watch7,12", ordinal: 3))
    }

    @Test("Derived record identities use the RFC 9562 custom UUID version")
    @available(iOS 18, *)
    func identityUsesUUIDVersion8() {
        var uuid = derive(at: firstCoordinate, ordinal: 3).uuid.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }

        #expect(bytes[6] >> 4 == 8)
        #expect(bytes[8] & 0xC0 == 0x80)
    }

    @available(iOS 18, *)
    private func derive(
        at coordinate: SensorKit.AcquisitionBatchCoordinate,
        sourceToken: String = "SRSensor.accelerometer",
        deviceProductType: String = "iPhone18,2",
        ordinal: UInt64
    ) -> SensorKitSourceRecordID {
        SensorKitSourceRecordID.derived(
            acquisitionBatch: coordinate,
            sourceToken: sourceToken,
            deviceProductType: deviceProductType,
            recordOrdinal: ordinal
        )
    }
}

#endif
