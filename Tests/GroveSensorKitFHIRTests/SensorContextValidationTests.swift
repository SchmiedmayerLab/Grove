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
import ModelsR4
import Testing


/// The converter refuses a context that names a repository row for a node the graph will not carry.
@Suite
struct SensorFHIRContextValidationTests {
    private static let start = Date(timeIntervalSince1970: 1_787_009_400)

    private static func context(repositoryIDs: [ExchangeGraphNode: RepositoryID]) -> SensorConversionContext {
        SensorConversionContext(
            converter: .test(
                name: "Grove Conformance Fixture",
                bundleIdentifier: "org.grovealliance.conformance-fixture",
                version: "0.5.0"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
            conversionInstant: start.addingTimeInterval(20),
            repositoryIDs: repositoryIDs
        )
    }

    private static func record() throws -> SensorRecord {
        .recordingDocument(try SensorRecordingDocument(
            identifier: BusinessIdentifier(
                system: "https://study.example.org/fhir/identifiers/sensorkit-record",
                value: "ambient-light-1"
            ),
            sourceTypeIdentifier: "SRSensor.ambientLightSensor",
            type: SensorCode(
                system: "https://grovealliance.org/fhir/sensor/CodeSystem/grove-sensor-recording",
                code: "ambient-light",
                display: "Ambient light"
            ),
            title: "Ambient light recording",
            format: .ambientLightSamples,
            payload: .inline(Data(
                "timestamp,lux,placement,chromaticityX,chromaticityY,device\n0,120,frontTop,0.3,0.4,iPhone18\n".utf8
            )),
            rawPayloadAdmission: .verifiedSanitizedInput
        ))
    }

    @Test("A recording-device repository row without a recording device is rejected")
    func rejectsRecordingDeviceRowWithoutDevice() throws {
        let context = Self.context(repositoryIDs: [.recordingDevice: try RepositoryID("device-1")])
        #expect(throws: SensorConversionError.repositoryIDWithoutRecordingDevice) {
            try SensorConverter().convert(Self.record(), context: context)
        }
    }

    @Test("A batch reports the typed reason for each rejected record rather than relabelling it")
    func batchReportsTypedReasons() throws {
        let context = Self.context(repositoryIDs: [.recordingDevice: try RepositoryID("device-1")])
        let result = SensorConverter().convert([try Self.record()], context: context)
        #expect(result.conversions.isEmpty)
        #expect(result.failures.map(\.reason) == [.repositoryIDWithoutRecordingDevice])
    }
}
