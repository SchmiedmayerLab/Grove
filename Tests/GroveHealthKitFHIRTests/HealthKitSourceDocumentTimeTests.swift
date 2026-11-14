//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


struct HealthKitSourceDocumentTimeTests {
    @Test
    func clinicalDownloadTimeStaysOnTheSourceEntityAndNeverRewritesHistoricalCareDates() async throws {
        let bytes = Data("{\"resourceType\":\"Observation\",\"effectiveDateTime\":\"2000-01-01T00:00:00Z\"}".utf8)
        let sample = try StoredSampleFixtures.clinicalRecord(
            HKClinicalType(.labResultRecord), fhirVersion: .primaryR4(), resource: bytes, facts: GoldenCase.seriesFacts(uuid: 0xF3, duration: 10)
        )
        let conversion = try await ExporterFixtures.export(sample)
        let evidence = try #require(conversion.provenance.entity?.first?.extension?.filter { $0.url == HealthKitSourceDocumentTime.extensionURL })
        #expect(evidence.count == 1)
        #expect(evidence[0].extension?.first?.value == .code(FHIRPrimitive(FHIRString(HealthKitSourceDocumentTime.Basis.clinicalRecordDownload.rawValue))))
        let periodElement = try #require(evidence[0].extension?.last)
        guard case .period(let period) = periodElement.value else {
            Issue.record("Missing source period")
            return
        }
        let sourceZone = try #require(TimeZone(identifier: GoldenFixtures.timeZone))
        let expected = try HealthKitEffectiveTime.period(start: sample.startDate, end: sample.endDate, zone: sourceZone)
        #expect(period == expected)
        #expect(conversion.document.context?.period == nil)
        #expect(conversion.document.content.first?.attachment.data?.value?.dataString == bytes.base64EncodedString())
    }

    @MainActor
    @Test
    func cdaUsesItsOwnSourceAssignedBasisRatherThanClinicalRecordDownloadMeaning() async throws {
        let sample = try HKCDADocumentSample(
            data: Data(GoldenCase.clinicalDocumentXML.utf8),
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_000_000),
            metadata: nil
        )
        let conversion = try await ExporterFixtures.export(sample)
        let evidence = try #require(conversion.provenance.entity?.first?.extension?.first { $0.url == HealthKitSourceDocumentTime.extensionURL })
        #expect(evidence.extension?.first?.value == .code(FHIRPrimitive(FHIRString(HealthKitSourceDocumentTime.Basis.cdaSourceDocumentPeriod.rawValue))))
        #expect(conversion.document.context?.period == nil)
        let periodElement = try #require(evidence.extension?.last)
        guard case .period(let period) = periodElement.value else {
            Issue.record("Missing source period")
            return
        }
        #expect(period.start == period.end)
    }
}

#endif
