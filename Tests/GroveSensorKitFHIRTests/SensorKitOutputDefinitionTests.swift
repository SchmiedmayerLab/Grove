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


struct SensorKitOutputDefinitionTests {
    @Test
    func deferredInventoryDoesNotBecomeProducerAvailability() throws {
        let rows = SensorKitCatalog.current.entries
        #expect(rows.compactMap(\.implementedOutput).count == 21)
        #expect(rows.filter { $0.status == .deferred }.allSatisfy { $0.implementedOutput == nil })
        for row in rows {
            guard let output = row.implementedOutput else { continue }
            #expect(output.recordingFormats == row.rawFormats)
            #expect(output.recordingProfiles == row.rawProfiles)
            #expect(output.observation?.profiles == row.structuredContract.map { _ in row.structuredProfiles })
            if let observation = output.observation {
                #expect(observation.primaryProfile != nil)
                #expect(output.requiredCompanionProfiles == (
                    observation.requiresRecording ? [SensorKitContract.recordingDocumentProfile] : []
                ))
            }
        }
    }

    @Test(arguments: [false, true])
    func onWristDescriptorMatchesActualPointAndIntervalOutput(interval: Bool) async throws {
        let instant = SensorKitExporterFixtures.instant
        let input = SensorKitRecord.onWrist(.init(
            sourceRecordID: .init(UUID()),
            timestamp: instant,
            onWrist: true,
            currentStateStart: interval ? instant.addingTimeInterval(-60) : instant,
            wristLocation: .left,
            crownOrientation: .right
        ))
        let output = try #require(SensorKitCatalog.current.entry(sourceToken: input.sourceToken)?.implementedOutput?.observation)
        #expect(output.effective == .dateTimeOrPeriod)
        #expect(output.valueShape == .coded)
        #expect(!output.requiresRecording)
        let record = try await SensorKitExporterFixtures.record(input)
        let observation = try #require(record.graph.bundle.entry?.compactMap { entry -> Observation? in
            if case .observation(let observation)? = entry.resource { observation } else { nil }
        }.first)
        #expect(observation.meta?.profile?.map { $0.value?.url.absoluteString } == output.profiles.map(Optional.some))
        if interval {
            guard case .period = observation.effective else {
                Issue.record("Missing declared interval")
                return
            }
        } else {
            guard case .dateTime = observation.effective else {
                Issue.record("Missing declared point")
                return
            }
        }
        guard case .codeableConcept = observation.value else {
            Issue.record("Missing declared coded value")
            return
        }
        #expect(observation.component?.count == 2)
    }
}
