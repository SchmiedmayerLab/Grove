//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import Testing


/// A failure no refusal of this domain models.
struct UnmodelledConversionFailure: Error {}


/// How a failure raised while converting or retracting one record becomes the refusal the exporter reports.
@Suite
struct HealthKitConversionErrorTests {
    @Test("Every conversion failure narrows to the refusal domain by its type")
    func failuresNarrowToTheRefusalDomain() {
        func narrowed(_ error: any Error, source: HealthKitSourceType? = .heartRate) -> HealthKitConversionError {
            HealthKitConversionError(conversionFailure: error, source: source)
        }
        let valueFailure = HealthKitConversionError.ValueFailure.outsideDomain
        #expect(narrowed(HealthKitConversionError.conflictingDuplicate) == .conflictingDuplicate)
        #expect(narrowed(valueFailure) == .invalidValue(.heartRate, .outsideDomain))
        #expect(narrowed(valueFailure, source: nil) == .dependency(String(reflecting: HealthKitConversionError.ValueFailure.self)))
        #expect(narrowed(ExchangeIdentityError.invalidInstant) == .exchangeIdentity(.invalidInstant))
        #expect(narrowed(ExchangeGraphError.missingTimestamp) == .exchangeGraph(.missingTimestamp))
        #expect(narrowed(UnmodelledConversionFailure()) == .dependency(String(reflecting: UnmodelledConversionFailure.self)))
    }

    /// A FHIR date failure describes the participant's instant, so a dependency refusal names the failure's type alone.
    @Test("A deletion bound no FHIR dateTime can state is refused as a dependency naming the failure's type alone")
    func unstatableDeletionBoundIsADependencyRefusal() async throws {
        let afterYear9999 = Date(timeIntervalSince1970: 253_402_300_800)
        let (retractions, _) = try await ExporterFixtures.retract(
            try ExporterFixtures.exporter(),
            [ExporterFixtures.deletion(0xC9, detectedAt: afterYear9999)]
        )
        guard case .refused(let refusal) = retractions.first?.outcome else {
            Issue.record("expected a refusal, got \(String(describing: retractions.first?.outcome))")
            return
        }
        #expect(refusal == .dependency("GroveFHIRContract.RetractionEvent.ValidationError"))
        #expect(refusal.diagnostic.code == ExchangeGraphRule.mobileInputUnclassified.rawValue)
    }
}

#endif
