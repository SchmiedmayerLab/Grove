//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


@Suite
struct RecordingBatchCounterTests {
    @Test
    func repeatedAndInterleavedRowsCountEachPairOnce() throws {
        var counter = RecordingBatchCounter()
        for (device, identifier) in [("Watch", 1), ("Phone", 1), ("Watch", 2), ("Watch", 1), ("Phone", 1)] {
            try counter.add(device: device, identifier: UInt64(identifier))
        }
        #expect(counter.count == 3)
        // Canonically equivalent device names are one device, as Swift strings compare.
        try counter.add(device: "Caf\u{E9}", identifier: 7)
        try counter.add(device: "Cafe\u{301}", identifier: 7)
        try counter.add(device: "Watch", identifier: .max)
        #expect(counter.count == 5)
    }

    @Test
    func limitIsInclusiveAndKnownBatchesStillCount() throws {
        var counter = RecordingBatchCounter()
        for identifier in 0..<UInt64(RecordingBatchCounter.maximumBatchCount) {
            try counter.add(device: "Watch", identifier: identifier)
        }
        #expect(counter.count == RecordingBatchCounter.maximumBatchCount)
        try counter.add(device: "Watch", identifier: 0)
        #expect(throws: SensorKitSummaryError.batchLimitExceeded(maximumBatchCount: 1_000_000)) {
            try counter.add(device: "Phone", identifier: 0)
        }
        #expect(counter.count == RecordingBatchCounter.maximumBatchCount)
    }

    @Test
    func deviceLimitIsInclusive() throws {
        var counter = RecordingBatchCounter()
        for device in 0..<RecordingBatchCounter.maximumDeviceCount {
            try counter.add(device: "Device \(device)", identifier: 1)
        }
        try counter.add(device: "Device 0", identifier: 2)
        #expect(throws: SensorKitSummaryError.deviceLimitExceeded(maximumDeviceCount: 16)) {
            try counter.add(device: "Device 16", identifier: 1)
        }
        #expect(counter.count == RecordingBatchCounter.maximumDeviceCount + 1)
    }

    @Test("A recording over a summary limit throws the public error when its record is created")
    func accelerometerRecordThrowsTheSummaryLimit() throws {
        let sourceID = SensorKitSourceRecordID(try #require(UUID(uuidString: "879d9ea2-21cb-4527-b59b-2831dc4c84ab")))
        func record(_ rows: some Sequence<(identifier: Int, device: String)>) throws -> SensorKitAccelerometerRecord {
            var csv = "timestamp,identifier,x,y,z,device\n"
            for row in rows {
                csv += "1787009400,\(row.identifier),0.1,0.2,0.3,\(row.device)\n"
            }
            let recording = try SensorKitNativeRecording(
                title: "Accelerometer batch",
                format: .triaxialAccelerationSamples,
                payload: .inline(Data(csv.utf8)),
                admission: .verifiedSanitizedInput
            )
            return try SensorKitAccelerometerRecord(sourceRecordID: sourceID, nativeRecording: recording)
        }
        let batches = (0...RecordingBatchCounter.maximumBatchCount).lazy.map { (identifier: $0, device: "Watch") }
        #expect(throws: SensorKitSummaryError.batchLimitExceeded(maximumBatchCount: 1_000_000)) { try record(batches) }
        let devices = (0...RecordingBatchCounter.maximumDeviceCount).map { (identifier: 1, device: "Watch\($0)") }
        #expect(throws: SensorKitSummaryError.deviceLimitExceeded(maximumDeviceCount: 16)) { try record(devices) }
    }
}
