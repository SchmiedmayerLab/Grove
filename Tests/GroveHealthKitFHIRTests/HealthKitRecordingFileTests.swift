//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


struct HealthKitRecordingFileTests {
    private enum ReadFailure: Error { case interrupted }

    @Test
    func routeFilePreservesBytesAndSourceEnvelopeAndHonorsDisclosure() async throws {
        let route = try Self.sample(HKWorkoutRoute.self, type: HKSeriesType.workoutRoute(), count: 2)
        let locations = Self.locations(count: 2)
        let prepared = try await HealthKitRecordingFile.workoutRoute(
            route, locations: Self.sequence(locations), relativePath: "recordings/route.csv", maximumByteCount: 4096
        )
        let expected = try HealthKitContentPlan[.workoutRoute].recordingDocument().locationTrack(locations)
        var actual = Data()
        try prepared.file.readChunks { actual.append($0) }
        #expect(actual == expected)
        var inputs = ExportInputs()
        inputs.options.route = .authorized
        let inline = try await ExporterFixtures.export(.workoutRoute(route, locations: locations), inputs)
        let external = try await ExporterFixtures.export(.fileRecording(prepared), inputs)
        let original = try #require(inline.document.content.first?.attachment)
        let attachment = try #require(external.document.content.first?.attachment)
        #expect(attachment.data == nil && attachment.url?.value?.url.absoluteString == prepared.relativePath)
        #expect(attachment.hash == original.hash && attachment.size == original.size)
        #expect(external.document.context == inline.document.context)
        #expect(external.document.extension == inline.document.extension)
        #expect(external.document.identifier == inline.document.identifier)
        #expect(try await ExporterFixtures.exports(.fileRecording(prepared)).isEmpty)
    }

    @Test
    func heartbeatFileUsesTheSameExactTimestampAndGapEncoding() async throws {
        let series = try Self.sample(HKHeartbeatSeriesSample.self, type: HKSeriesType.heartbeat(), count: 2)
        let beats: [HealthKitFHIRExporter.Record.Heartbeat] = [
            .init(timeSinceSeriesStart: 0.1234567, precededByGap: false), .init(timeSinceSeriesStart: 0.9876543, precededByGap: true)
        ]
        let prepared = try await HealthKitRecordingFile.heartbeatSeries(
            series, beats: Self.sequence(beats), relativePath: "recordings/beats.csv", maximumByteCount: 4096
        )
        var actual = Data()
        try prepared.file.readChunks { actual.append($0) }
        let expected = try HealthKitContentPlan[.heartbeatSeries].recordingDocument().beatIntervals(
            seriesStart: series.startDate, heartbeats: beats
        )
        #expect(actual == expected)
        let converted = try await ExporterFixtures.export(.fileRecording(prepared))
        #expect(converted.document.content.first?.attachment.data == nil)
        #expect(converted.document.content.first?.attachment.size?.value?.integer == Int32(expected.count))
    }

    @Test
    func queryFailureAfterOneFixCannotReturnAPartialRecording() async throws {
        let route = try Self.sample(HKWorkoutRoute.self, type: HKSeriesType.workoutRoute(), count: 2)
        let locations = Self.locations(count: 1)
        let results = AsyncThrowingStream<CLLocation, any Error> { continuation in
            continuation.yield(locations[0])
            continuation.finish(throwing: ReadFailure.interrupted)
        }
        await #expect(throws: ReadFailure.self) {
            try await HealthKitRecordingFile.workoutRoute(route, locations: results, relativePath: "route.csv", maximumByteCount: 4096)
        }
    }

    @Test
    func cancellationDuringReadCannotFinalizeARecording() async throws {
        let route = try Self.sample(HKWorkoutRoute.self, type: HKSeriesType.workoutRoute(), count: 1)
        let task = Task {
            let locations = Self.sequence(Self.locations(count: 1)).map { location in
                withUnsafeCurrentTask { $0?.cancel() }
                return location
            }
            return try await HealthKitRecordingFile.workoutRoute(route, locations: locations, relativePath: "route.csv", maximumByteCount: 4096)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func exactByteLimitIsAcceptedAndOneByteLessFails() async throws {
        let route = try Self.sample(HKWorkoutRoute.self, type: HKSeriesType.workoutRoute(), count: 2)
        let locations = Self.locations(count: 2)
        let expected = try HealthKitContentPlan[.workoutRoute].recordingDocument().locationTrack(locations)
        let prepared = try await HealthKitRecordingFile.workoutRoute(
            route, locations: Self.sequence(locations), relativePath: "route.csv", maximumByteCount: expected.count
        )
        #expect(prepared.file.byteCount == expected.count)
        await #expect(throws: RecordingCSVFileWriter.FileWriterError.payloadLimitExceeded) {
            try await HealthKitRecordingFile.workoutRoute(
                route, locations: Self.sequence(locations), relativePath: "route.csv", maximumByteCount: expected.count - 1
            )
        }
    }

    @Test
    func invalidBeatCannotProduceAFile() async throws {
        let series = try Self.sample(HKHeartbeatSeriesSample.self, type: HKSeriesType.heartbeat(), count: 2)
        let beats: [HealthKitFHIRExporter.Record.Heartbeat] = [
            .init(timeSinceSeriesStart: 0, precededByGap: false), .init(timeSinceSeriesStart: .infinity, precededByGap: false)
        ]
        await #expect(throws: RecordingCSVWriter.WriterError.nonFiniteNumber(column: "timestamp")) {
            try await HealthKitRecordingFile.heartbeatSeries(
                series, beats: Self.sequence(beats), relativePath: "beats.csv", maximumByteCount: 4096
            )
        }
    }

    @Test(arguments: [0, 1, 3])
    func truncatedAndExcessRouteSamplesCannotProduceAFile(count: Int) async throws {
        let route = try Self.sample(HKWorkoutRoute.self, type: HKSeriesType.workoutRoute(), count: 2)
        await #expect(throws: HealthKitRecordingFile.RecordingError.incompleteSeries) {
            try await HealthKitRecordingFile.workoutRoute(
                route, locations: Self.sequence(Self.locations(count: count)), relativePath: "route.csv", maximumByteCount: 4096
            )
        }
    }

    @Test(arguments: ["/route.csv", "../route.csv", "a//route.csv", "https://example.invalid/route.csv", "a%2Fb.csv", "%2e%2e/a.csv", "a?token=1"])
    func attachmentPathsRemainLocalAndRelative(path: String) async throws {
        let route = try Self.sample(HKWorkoutRoute.self, type: HKSeriesType.workoutRoute(), count: 1)
        await #expect(throws: HealthKitRecordingFile.RecordingError.invalidRelativePath) {
            try await HealthKitRecordingFile.workoutRoute(
                route, locations: Self.sequence(Self.locations(count: 1)), relativePath: path, maximumByteCount: 4096
            )
        }
    }
}


extension HealthKitRecordingFileTests {
    private static func sample<Sample: HKSeriesSample>(_ type: Sample.Type, type sampleType: HKSeriesType, count: Int) throws -> Sample {
        let sample = try StoredSampleFixtures.seriesSample(type, sampleType: sampleType, facts: .init(
            uuid: GoldenFixtures.uuid(0xFA),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(2),
            device: nil,
            metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"],
            writer: GoldenFixtures.foreignWriter
        ))
        if sample is HKHeartbeatSeriesSample {
            try StoredSampleFixtures.restate(sample, with: ["numberOfDataPoints": NSNumber(value: count)])
        } else {
            try StoredSampleFixtures.restate(sample, with: ["count": NSNumber(value: count)])
        }
        try #require(sample.count == count)
        return sample
    }

    private static func locations(count: Int) -> [CLLocation] {
        (0..<count).map { index in
            CLLocation(
                coordinate: .init(latitude: 37, longitude: -122),
                altitude: 10,
                horizontalAccuracy: 1,
                verticalAccuracy: -1,
                timestamp: GoldenFixtures.sampleStart.addingTimeInterval(Double(index))
            )
        }
    }

    private static func sequence<Element: Sendable>(_ values: [Element]) -> AsyncThrowingStream<Element, any Error> {
        AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
}

#endif
