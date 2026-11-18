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
public import GroveSensorKit
public import SensorKit


extension SensorKitPreparedStructuredFile {
    /// Streams individual applications, notifications, web entries and text-input sessions in source order.
    /// The resulting native JSON and clinical summary preserve the complete public report.
    @available(iOS 18, *)
    public init(deviceUsage report: SRDeviceUsageReport.SafeRepresentation, maximumByteCount: Int) throws {
        let writer = SensorKitJSONFileEncoding()
        let file = try RecordingFile.stage(
            maximumByteCount: min(maximumByteCount, RegisteredRecordingFormat.maximumDecodedPayloadByteCount)
        ) { append in
            try writer.object(DeviceUsageEvidence.CodingKeys.allCases, name: \.rawValue, append: append) { key in
                switch key {
                case .timestamp: try writer.value(report.timestamp, append: append)
                case .duration: try writer.value(report.duration, append: append)
                case .totalScreenWakes: try writer.value(report.totalScreenWakes, append: append)
                case .totalUnlocks: try writer.value(report.totalUnlocks, append: append)
                case .totalUnlockDuration: try writer.value(report.totalUnlockDuration, append: append)
                case .version: try writer.value(report.version, append: append)
                case .appUsageByCategory:
                    try writer.categoryValues(report.appUsageByCategory, append: append) { try writer.applicationUsage($0, append: append) }
                case .notificationUsageByCategory:
                    try writer.categoryValues(report.notificationUsageByCategory, append: append) {
                        try writer.value(DeviceUsageEvidence.NotificationUsage(
                            bundleIdentifier: $0.bundleIdentifier, eventRawValue: $0.event.rawValue
                        ), append: append)
                    }
                case .webUsageByCategory:
                    try writer.categoryValues(report.webUsageByCategory, append: append) {
                        try writer.value(DeviceUsageEvidence.WebUsage(totalUsageTime: $0.totalUsageTime), append: append)
                    }
                }
            }
        }
        self.init(file: file) { sourceID, native in
            .deviceUsage(SensorKitDeviceUsageRecord(sourceRecordID: sourceID, report: report, nativeRecording: native))
        }
    }
}


@available(iOS 18, *)
extension SensorKitJSONFileEncoding {
    fileprivate func categoryValues<Value>(
        _ categories: [SRDeviceUsageReport.CategoryKey: [Value]], append: (Data) throws -> Void, element: (Value) throws -> Void
    ) throws {
        let values = Dictionary(uniqueKeysWithValues: categories.map { ($0.key.rawValue, $0.value) })
        try object(Array(values.keys), name: { $0 }, append: append) { key in
            try array(values[key, default: []], append: append, element: element)
        }
    }

    fileprivate func applicationUsage(_ usage: SRDeviceUsageReport.SafeRepresentation.AppUsage, append: (Data) throws -> Void) throws {
        let keys = DeviceUsageEvidence.ApplicationUsage.CodingKeys.allCases.filter { $0 != .bundleIdentifier || usage.bundleIdentifier != nil }
        try object(keys, name: \.rawValue, append: append) { key in
            switch key {
            case .bundleIdentifier: try value(usage.bundleIdentifier, append: append)
            case .reportApplicationIdentifier: try value(usage.reportApplicationIdentifier, append: append)
            case .relativeStartTime: try value(usage.relativeStartTime, append: append)
            case .usageTime: try value(usage.usageTime, append: append)
            case .supplementalCategories:
                try array(usage.supplementalCategories.sorted { $0.identifier < $1.identifier }, append: append) {
                    try value(DeviceUsageEvidence.ApplicationUsage.SupplementalCategory(identifier: $0.identifier), append: append)
                }
            case .textInputSessions:
                try array(usage.textInputSessions, append: append) {
                    try value(DeviceUsageEvidence.ApplicationUsage.TextInputSession(
                        duration: $0.duration, sessionTypeRawValue: $0.sessionType.rawValue, identifier: $0.identifier
                    ), append: append)
                }
            }
        }
    }
}
#endif
