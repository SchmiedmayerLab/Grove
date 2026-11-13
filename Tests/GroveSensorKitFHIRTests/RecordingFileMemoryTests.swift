//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Darwin
import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


/// Opt-in measurement: run each workload in a fresh test process so the kernel lifetime peak is attributable.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GROVE_RECORDING_MEMORY_MIB"] != nil), .timeLimit(.minutes(10)))
struct RecordingFileMemoryTests {
    private struct Footprint: Encodable {
        let current: UInt64
        let peak: UInt64
    }

    private struct Measurement: Encodable {
        let payloadBytes: Int
        let distinctBatches: Int
        let baselineBytes: UInt64
        let lifetimePeakBytes: UInt64
        let excessBytes: UInt64
        let maximumExcessBytes: UInt64
        let phases: [String: Footprint]
    }

    @Test
    func largeRecordingHasBoundedWorkingMemory() async throws {
        let megabytes = try #require(ProcessInfo.processInfo.environment["GROVE_RECORDING_MEMORY_MIB"].flatMap(Int.init))
        try #require((1...512).contains(megabytes))
        let baseline = try footprint()
        let fixture = try RecordingFileFixture(Data())
        defer { withExtendedLifetime(fixture) {} }
        let size = try generateCSV(at: fixture.source, minimumBytes: megabytes * 1024 * 1024)
        let generated = try footprint()
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: Int64(size.bytes))
        let staged = try footprint()
        let input = try SensorKitNativeRecording(
            title: "Acceleration recording",
            format: .triaxialAccelerationSamples,
            payload: .file(path: "recordings/acceleration.csv", contents: file),
            admission: .verifiedSanitizedInput
        )
        let validated = try footprint()
        let summary = try SensorKitAccelerometerRecord(sourceRecordID: .init(UUID()), nativeRecording: input)
        let summarized = try footprint()
        #expect(summary.sampleCount == size.rows && summary.batchCount == size.rows)
        let record = try await SensorKitExporterFixtures.record(.accelerometer(summary))
        #expect(record.json.count < 32 * 1024)
        let end = try footprint()
        let excess = end.peak > baseline.current ? end.peak - baseline.current : 0
        let measurement = Measurement(
            payloadBytes: file.byteCount,
            distinctBatches: size.rows,
            baselineBytes: baseline.current,
            lifetimePeakBytes: end.peak,
            excessBytes: excess,
            maximumExcessBytes: 64 * 1024 * 1024,
            phases: ["generated": generated, "staged": staged, "validated": validated, "summarized": summarized, "exported": end]
        )
        print("RECORDING_MEMORY " + String(decoding: try JSONEncoder().encode(measurement), as: UTF8.self))
        #expect(excess <= measurement.maximumExcessBytes)
        withExtendedLifetime(file) {}
    }

    /// Every row has a distinct batch key, so a retained Set would grow with the workload.
    private func generateCSV(at url: URL, minimumBytes: Int) throws -> (bytes: Int, rows: Int) {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var buffer = Data("timestamp,identifier,x,y,z,device\n".utf8)
        var written = 0
        var rows = 0
        while written + buffer.count < minimumBytes {
            buffer.append(contentsOf: "1787009400,\(rows),0.1,0.2,0.3,Watch\n".utf8)
            rows += 1
            if buffer.count >= 64 * 1024 {
                try autoreleasepool { try handle.write(contentsOf: buffer) }
                written += buffer.count
                buffer.removeAll(keepingCapacity: true)
            }
        }
        try handle.write(contentsOf: buffer)
        return (written + buffer.count, rows)
    }

    private func footprint() throws -> Footprint {
        var info = task_vm_info_data_t()
        let capacity = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        try #require(result == KERN_SUCCESS)
        let peakOffset = try #require(MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak))
        try #require(Int(count) * MemoryLayout<integer_t>.size >= peakOffset + MemoryLayout<Int64>.size)
        try #require(info.ledger_phys_footprint_peak >= 0)
        try #require(UInt64(info.ledger_phys_footprint_peak) >= info.phys_footprint)
        return Footprint(current: info.phys_footprint, peak: UInt64(info.ledger_phys_footprint_peak))
    }
}
