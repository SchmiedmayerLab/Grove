//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation


@available(iOS 18, *)
extension SensorKit {
    /// Fetches exactly one retained native batch using an isolated copy of its original pending anchor.
    /// The caller must compare the ordered source digests with its retained receipt before using any result.
    /// Missing, reordered or expired history is an error; it never silently advances a live cursor.
    public func replay<Sample>(
        _ token: BatchReplayToken, from sensor: Sensor<Sample>, ecgProcessingLimits: SensorKitECGProcessingLimits = .init()
    ) async throws -> AnchoredBatch<Sample.SafeRepresentation> {
        try Task.checkCancellation()
        guard token.sensorIdentifier == sensor.id else { throw BatchReplayError.sourceMismatch }
        let devices = try await sensor.fetchDevices()
        try Self.validateUniqueDevicePartitions(devices.map(\.productType))
        guard let device = devices.first(where: { $0.productType == token.deviceProductType }) else {
            throw BatchReplayError.deviceUnavailable
        }
        let anchor = ManagedQueryAnchor.ephemeral(anchor: token.anchor)
        guard let pending = token.anchor.pendingBatch else { throw BatchReplayError.invalidToken }
        let result: AnchoredBatch<Sample.SafeRepresentation>?
        switch pending.mode {
        case .sampleCount:
            let iterator = AnchoredFetcher<Sample>.SampleCountBasedFetcher(
                sensor: sensor, batchSize: pending.sampleCount, anchor: anchor, device: device, ecgProcessingLimits: ecgProcessingLimits
            )
            result = try await iterator.next(isolation: nil)
        case .timeRange:
            var iterator = AnchoredFetcher<Sample>.TimeIntervalBasedFetcher(
                sensor: sensor,
                anchor: anchor,
                quarantineCutoff: sensor.currentQuarantineBegin,
                batchSize: pending.upperBound.timeIntervalSince(pending.lowerBound ?? pending.upperBound),
                device: device
            )
            result = try await iterator.next(isolation: nil)
        }
        try Task.checkCancellation()
        guard let result, result.info.replayToken == token else { throw BatchReplayError.batchUnavailable }
        return result
    }
}
