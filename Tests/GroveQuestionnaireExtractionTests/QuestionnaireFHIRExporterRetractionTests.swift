//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
@testable import GroveQuestionnaireExtraction
import ModelsR4
import Testing


/// A projected response's outputs are withdrawn through the retraction path against their own source-output identifiers
/// (questionnaire guide `responses.md`, lifecycle and participation metadata).
@Suite("Questionnaire Retraction")
struct QuestionnaireFHIRExporterRetractionTests {
    private typealias Fixtures = QuestionnaireExportFixtures

    private static let withdrawnAt = Fixtures.instant.addingTimeInterval(86_400)

    private static func retract(
        _ exporter: QuestionnaireFHIRExporter,
        _ withdrawals: [QuestionnaireFHIRExporter.Withdrawal],
        at instant: Date = withdrawnAt
    ) throws -> (retractions: [QuestionnaireFHIRExporter.Retraction], receipt: ExchangeProducer.Receipt) {
        var retractions: [QuestionnaireFHIRExporter.Retraction] = []
        let receipt = try exporter.retract(withdrawals, at: instant) { retractions.append($0) }
        return (retractions, receipt)
    }

    private static func identifier(_ observation: Observation, _ role: GroveIdentifierRole) -> Identifier? {
        observation.identifier?.first { (try? RoledIdentifier($0))?.role == role }
    }

    @Test("A retraction targets exactly the Observations the export emitted, under their source-output identities")
    func targetsTheExportedObservations() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let record = try Fixtures.guideRecord()
        let exported = try #require(try Fixtures.collect(exporter, [record]).exports.first?.graph)
        let (retractions, _) = try Self.retract(exporter, [.init(record: record, withdrawnAt: Self.withdrawnAt)])
        #expect(retractions.map(\.responseIdentifier) == ["home-vitals-2026-08-28"])
        let graph = try #require(retractions.first?.graph)
        #expect(graph.kind == .retraction)
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)

        let outputs = exported.observations.compactMap { Self.identifier($0, .sourceOutput) }
        #expect(outputs.count == exported.observations.count && !outputs.isEmpty)
        #expect(provenance.target.compactMap(\.identifier) == outputs)
        for target in provenance.target {
            #expect(target.type?.value?.url.absoluteString == "Observation")
            let roles = (target.extension ?? []).filter { $0.url == Canonicals.retractionTargetRole }.compactMap { role -> String? in
                if case .code(let code)? = role.value { code.value?.string } else { nil }
            }
            #expect(roles == ["primary-output"])
        }
        let sourceRecord = try #require(exported.observations.first.flatMap { Self.identifier($0, .sourceRecord) })
        #expect(provenance.entity?.map(\.what.identifier) == [sourceRecord])
        #expect(provenance.occurred == .dateTime(FHIRPrimitive(try ExchangeInstant.fhirDateTime(Self.withdrawnAt))))
    }

    @Test("An exact retry before release restates the retraction; another instant or a release mints a new event")
    func retryBeforeReleaseRestatesTheEvent() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let withdrawal = QuestionnaireFHIRExporter.Withdrawal(record: try Fixtures.guideRecord(), withdrawnAt: Self.withdrawnAt)
        let (first, receipt) = try Self.retract(exporter, [withdrawal])
        let event = try #require(first.first?.graph?.eventIdentifier)
        let (again, againReceipt) = try Self.retract(exporter, [withdrawal], at: Self.withdrawnAt.addingTimeInterval(60))
        #expect(again.map(\.graph?.json) == first.map(\.graph?.json))

        let reported = QuestionnaireFHIRExporter.Withdrawal(record: withdrawal.record, withdrawnAt: Self.withdrawnAt.addingTimeInterval(1))
        let later = try Self.retract(exporter, [reported]).retractions
        #expect(later.first?.graph.map(\.eventIdentifier) != event)

        receipt.release()
        againReceipt.release()
        let next = try Self.retract(exporter, [withdrawal]).retractions
        #expect(next.first?.graph.map(\.eventIdentifier) != event)
    }

    @Test("Releasing a retraction forgets the active reservation an unreleased export left behind")
    func releaseForgetsTheActiveReservation() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let record = try Fixtures.guideRecord()
        // Each export's receipt lapses unreleased, as a call that threw does, and leaves its event for the redelivery.
        let exported = try #require(try Fixtures.collect(exporter, [record]).exports.first?.graph)
        let redelivered = try #require(try Fixtures.collect(exporter, [record]).exports.first?.graph)
        #expect(redelivered.eventIdentifier == exported.eventIdentifier)

        try Self.retract(exporter, [.init(record: record, withdrawnAt: Self.withdrawnAt)]).receipt.release()
        let after = try #require(try Fixtures.collect(exporter, [record]).exports.first?.graph)
        #expect(after.eventIdentifier != exported.eventIdentifier, "the released retraction forgot the export's event")
    }

    @Test("A pair the export refuses is refused alike, reserves nothing, and the call goes on")
    func refusedPairReservesNothing() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let inProgress = try Fixtures.guideRecord { $0.status = FHIRPrimitive(.inProgress) }
        let (retractions, _) = try Self.retract(exporter, [
            .init(record: inProgress, withdrawnAt: Self.withdrawnAt),
            .init(record: try Fixtures.guideRecord(), withdrawnAt: Self.withdrawnAt)
        ])
        guard case .refused(let refusal) = retractions.first?.outcome else {
            Issue.record("the in-progress response was not refused")
            return
        }
        #expect(refusal == .responseNotCompleted(status: "in-progress"))
        #expect(retractions.map { $0.graph?.eventIdentifier.sequence.rawValue } == [nil, "1"])
    }
}
