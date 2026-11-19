//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
import GroveFHIRContract
import GroveSensorKit
import GroveSensorKitFHIR
import SensorKit
import Testing


struct SensorKitStructuredFileTests {
    @available(iOS 18, *)
    @Test(arguments: [false, true])
    func deviceUsageFilePreservesEveryNestedFieldAndOptionalOmission(hasBundle: Bool) throws {
        let report = SRDeviceUsageReport.SafeRepresentation(
            timestamp: Date(timeIntervalSince1970: 1_787_009_400.125),
            duration: 300,
            totalScreenWakes: 3,
            totalUnlocks: 2,
            totalUnlockDuration: 42.5,
            version: "synthetic/1",
            appUsageByCategory: [
                // Names whose order depends on case and digit handling pin the file's member order to the in-memory encoding's.
                .init(rawValue: "Category-10"): [],
                .init(rawValue: "category-9"): [],
                .init(rawValue: "CATEGORY-2"): [],
                .init(rawValue: "category-b"): [],
                .init(rawValue: "category-a"): [
                    .init(
                        bundleIdentifier: hasBundle ? "org.example.synthetic" : nil,
                        relativeStartTime: 1.5,
                        usageTime: 3.25,
                        reportApplicationIdentifier: "app/one",
                        textInputSessions: [.init(duration: 1.25, sessionType: .keyboard, identifier: "input/one")],
                        supplementalCategories: [.init(identifier: "z"), .init(identifier: "a")]
                    )
                ]
            ],
            notificationUsageByCategory: [.init(rawValue: "notifications"): [.init(bundleIdentifier: nil, event: .received)]],
            webUsageByCategory: [.init(rawValue: "web"): [.init(totalUsageTime: 2.5)]]
        )
        let data = try SensorKitPreparedStructuredRecord(deviceUsage: report)
        let file = try SensorKitPreparedStructuredFile(deviceUsage: report, maximumByteCount: 16_384)
        var bytes = Data()
        try file.readRetryEvidenceChunks { bytes.append($0) }
        #expect(bytes == data.retryEvidence)
        #expect(bytes == data.nativePayload)
        try RegisteredRecordingFormat.nativeRecording.validatePayload(file.file, maximumByteCount: file.file.byteCount)
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try SensorKitPreparedStructuredFile(deviceUsage: report, maximumByteCount: file.file.byteCount - 1)
        }
        let exact = try SensorKitPreparedStructuredFile(deviceUsage: report, maximumByteCount: file.file.byteCount)
        #expect(exact.file.byteCount == file.file.byteCount)
    }
}
#endif
