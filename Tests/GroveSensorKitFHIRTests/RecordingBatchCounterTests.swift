//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveSensorKitFHIR
import Testing


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
        #expect(throws: RecordingBatchCounter.Failure.indexUnavailable) {
            try counter.add(device: "Phone", identifier: 0)
        }
        #expect(counter.count == RecordingBatchCounter.maximumBatchCount)
    }
}
