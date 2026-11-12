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


/// A projected response is withdrawn through the retraction path, which takes back its whole source record (questionnaire
/// guide `responses.md`, lifecycle and participation metadata).
@Suite("Questionnaire Retraction")
struct QuestionnaireFHIRExporterRetractionTests {
    private typealias Fixtures = QuestionnaireExportFixtures

    private static let withdrawnAt = Fixtures.instant.addingTimeInterval(86_400)

    private static func retract(
        _ exporter: QuestionnaireFHIRExporter,
        _ withdrawals: [QuestionnaireFHIRExporter.Withdrawal],
        at instant: Date = withdrawnAt
    ) async throws -> [QuestionnaireFHIRExporter.Retraction] {
        var retractions: [QuestionnaireFHIRExporter.Retraction] = []
        try await exporter.retract(withdrawals, at: instant) { retractions.append($0) }
        return retractions
    }

    /// The retraction of `record`, withdrawn at `withdrawnAt` and recorded at `instant`.
    private static func retraction(
        of record: QuestionnaireFHIRExporter.Record,
        withdrawnAt: Date = withdrawnAt,
        at instant: Date = withdrawnAt
    ) async throws -> ExchangeRecord {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        return try #require(try await retract(exporter, [.init(record: record, withdrawnAt: withdrawnAt)], at: instant).first?.record)
    }

    private static func identifier(_ observation: Observation, _ role: GroveIdentifierRole) -> Identifier? {
        observation.identifier?.first { (try? RoledIdentifier($0))?.role == role }
    }

    @Test("A retraction lists exactly the Observations the export emitted, under their source-output identities")
    func targetsTheExportedObservations() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let record = try Fixtures.guideRecord()
        let exported = try await #require(try Fixtures.collect(exporter, [record]).first?.record)
        let retractions = try await Self.retract(exporter, [.init(record: record, withdrawnAt: Self.withdrawnAt)])
        #expect(retractions.map(\.responseIdentifier) == ["home-vitals-2026-08-28"])
        let retraction = try #require(retractions.first?.record)
        #expect(retraction.kind == .retraction)
        #expect(retraction.outputFullURLs.isEmpty)
        let provenance = try retraction.provenance

        let observations = try exported.observations
        let outputs = observations.compactMap { Self.identifier($0, .sourceOutput) }
        #expect(outputs.count == observations.count && !outputs.isEmpty)
        #expect(provenance.target.compactMap(\.identifier) == outputs)
        for target in provenance.target {
            #expect(target.type?.value?.url.absoluteString == "Observation")
            let roles = (target.extension ?? []).filter { $0.url == Canonicals.retractionTargetRole }.compactMap { role -> String? in
                if case .code(let code)? = role.value { code.value?.string } else { nil }
            }
            #expect(roles == ["primary-output"])
        }
        let sourceRecord = try #require(observations.first.flatMap { Self.identifier($0, .sourceRecord) })
        #expect(provenance.entity?.map(\.what.identifier) == [sourceRecord])
        #expect(retraction.sourceRecord == exported.sourceRecord)
        #expect(provenance.occurred == .dateTime(FHIRPrimitive(try ExchangeInstant.fhirDateTime(Self.withdrawnAt))))
    }

    @Test("A retraction is keyed by its source record and carries no record version")
    func keyFollowsTheSourceRecord() async throws {
        let retraction = try await Self.retraction(of: Fixtures.guideRecord())
        #expect(retraction.version.identifier.role == .recordRetraction)
        #expect(try retraction.provenance.extension == nil)
        try retraction.verifyVersion(in: Fixtures.identityScope)
        #expect(try ExchangeRecord(validating: retraction.json).version == retraction.version)
    }

    @Test("A retraction's application Device states its Apple bundle identifier, as every adapter's does")
    func applicationDeviceStatesItsBundleIdentifier() async throws {
        let retraction = try await Self.retraction(of: Fixtures.guideRecord())
        let application = try #require(try retraction.devices.first { $0.parent != nil })
        let stated = (application.identifier ?? []).filter { $0.system == HealthKitContract.appleBundleIdentifierSystem }
        #expect(stated.map { $0.value?.value?.string } == ["org.grovealliance.example.app"])
    }

    /// The first accepted retraction of a source record wins, and every later report repeats its key.
    @Test("A retraction reported again repeats its key, whatever its instants")
    func reportedAgainRepeatsTheKey() async throws {
        let first = try await Self.retraction(of: Fixtures.guideRecord())
        let again = try await Self.retraction(of: Fixtures.guideRecord())
        #expect(again == first)
        let later = try await Self.retraction(
            of: Fixtures.guideRecord(),
            withdrawnAt: Self.withdrawnAt.addingTimeInterval(1),
            at: Self.withdrawnAt.addingTimeInterval(60)
        )
        #expect(later.json != first.json)
        #expect(later.version == first.version)
    }

    /// Only the source record addresses a retraction: it withdraws the whole response, whichever revision names it.
    @Test("A retraction of another revision of the pair takes back the same source record under the same key")
    func anotherRevisionHasTheSameKey() async throws {
        let guide = try await Self.retraction(of: Fixtures.guideRecord())
        let partial = try await Self.retraction(of: Fixtures.guideRecord { response in
            response.item = response.item?.filter { $0.linkId.value?.string != "blood-pressure" }
        })
        #expect(try partial.provenance.target.count == guide.provenance.target.count - 1)
        #expect(partial.sourceRecord == guide.sourceRecord)
        #expect(partial.version == guide.version)
    }

    @Test("The producer's application states the retraction, whichever writer the response names")
    func theProducerStatesTheRetraction() async throws {
        let retraction = try await Self.retraction(of: Fixtures.guideRecord())
        let names = try retraction.devices.compactMap { $0.deviceName?.first?.name.value?.string }
        #expect(names == ["Grove Example App"])
    }

    @Test("Retractions pack into a Bundle of their own, once per source record")
    func retractionsPackAlone() async throws {
        let other = try Fixtures.guideRecord { response in
            response.identifier = Identifier(system: response.identifier?.system, value: "home-vitals-2026-08-29")
        }
        let first = try await Self.retraction(of: Fixtures.guideRecord())
        let second = try await Self.retraction(of: other)
        var packer = ExchangeBundlePacker(kind: .retraction)
        #expect(try packer.insert(first) == .inserted)
        #expect(try packer.insert(second) == .inserted)
        #expect(try packer.insert(first) == .duplicate)
        let active = try await Fixtures.exported(Fixtures.guideRecord())
        #expect(throws: ExchangeBundlePacker.Failure.mixedKinds) {
            try packer.insert(active)
        }
        let bundle = try packer.bundle(packedAt: Self.withdrawnAt)
        #expect(bundle.kind == .retraction)
        #expect(try bundle.records().map(\.version) == [first.version, second.version])
    }

    @Test("A pair the export refuses is refused alike, and the call goes on")
    func refusedPairEmitsNothing() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let inProgress = try Fixtures.guideRecord { $0.status = FHIRPrimitive(.inProgress) }
        let retractions = try await Self.retract(exporter, [
            .init(record: inProgress, withdrawnAt: Self.withdrawnAt),
            .init(record: try Fixtures.guideRecord(), withdrawnAt: Self.withdrawnAt)
        ])
        guard case .refused(let refusal) = retractions.first?.outcome else {
            Issue.record("the in-progress response was not refused")
            return
        }
        #expect(refusal == .responseNotCompleted(status: "in-progress"))
        #expect(retractions.map { $0.record != nil } == [false, true])
    }

    @Test("A withdrawal instant no FHIR dateTime can state is refused, and a recorded instant none can state ends the call")
    func unstatableInstants() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let farFuture = Date(timeIntervalSince1970: 1e12)
        let retractions = try await Self.retract(exporter, [.init(record: try Fixtures.guideRecord(), withdrawnAt: farFuture)])
        guard case .refused(.exchangeIdentity(.invalidInstant))? = retractions.first?.outcome else {
            Issue.record("the withdrawal instant was not refused: \(String(describing: retractions.first?.outcome))")
            return
        }
        let withdrawal = QuestionnaireFHIRExporter.Withdrawal(record: try Fixtures.guideRecord(), withdrawnAt: Self.withdrawnAt)
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.retract([withdrawal], at: farFuture) { _ in }
        }
    }
}
