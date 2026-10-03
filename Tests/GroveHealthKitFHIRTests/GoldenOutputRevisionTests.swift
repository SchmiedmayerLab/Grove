//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import Testing


/// One checked-in golden file, its SHA-256 (base64url without padding), and the output revisions it was last
/// changed under.
struct GoldenRevision: Sendable, CustomTestStringConvertible {
    let name: String
    let digest: String
    let assembler: UInt
    let healthKit: UInt

    var testDescription: String { name }

    init(_ name: String, digest: String, assembler: UInt, healthKit: UInt) {
        self.name = name
        self.digest = digest
        self.assembler = assembler
        self.healthKit = healthKit
    }
}


/// Guards the output revisions the context fingerprint states.
///
/// An exact redelivery is byte-identical only while the converter emits the same bytes for the same inputs, so
/// any change that alters a golden must bump `ExchangeGraphAssembler.outputRevision` or
/// `HealthKitAssembly.outputRevision`. This table pins every golden file's digest: a changed golden fails here
/// until its row is updated, and the updated row must carry the bumped revision, which review checks in the
/// diff. A row never names a revision the code has not reached. A new golden adds a row without a bump.
@Suite
struct GoldenOutputRevisionTests {
    static let table: [GoldenRevision] = [
        GoldenRevision("blood-pressure-correlation", digest: "Cw-NT44sFRCYAsIii_BZXdS6r0gD2D8dMbV1_DYSuLE", assembler: 1, healthKit: 1),
        GoldenRevision("body-mass-user-entered", digest: "SFo9ZdasPxzkAQI2AcW0vlziFfAJyl2L5c-t5eHJdNY", assembler: 1, healthKit: 1),
        GoldenRevision("bundled-patient-subject", digest: "DdlaOOPCSIAMV1twtigLxjshiVzTqBaiO_YYaY-QOcA", assembler: 1, healthKit: 1),
        GoldenRevision("clinical-document", digest: "1asW-RkPmayr0J1cy__i-SxCb5c64dvfpMYFGkZdsOc", assembler: 1, healthKit: 1),
        GoldenRevision("electrocardiogram-symptom-companion", digest: "kr9x4zg2fLjcx8pXVU1zrNAkyOeXZDrOoDLW3QPA188", assembler: 1, healthKit: 1),
        GoldenRevision("electrocardiogram-with-symptom", digest: "9l2JtyHoAElz12UR_N0uGxnZo0YLw4X1vH-asSwgPfc", assembler: 1, healthKit: 1),
        GoldenRevision("electrocardiogram", digest: "4O8qSuiYKdJHCH6i1nQLwaj9Wj_WTXNJQSvGaTa4TZc", assembler: 1, healthKit: 1),
        GoldenRevision("gateway-application-role", digest: "1CfpIPrpl4EoRrQU9eimlM8i2ArNVdpbTk3mIAsBgXs", assembler: 1, healthKit: 1),
        GoldenRevision("gateway-role", digest: "JtaVascxlW4cJfq-aH6p2JDab9u-YfQiaSFtwvhiMFY", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-device-without-unit-token", digest: "gKIE0MA3n8uoEIiPTWI-TJOBDAD1osZVz6C0sWLibk8", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-interval", digest: "D4QTr9s6IiDjDLGr6Gm41p4QjU8Go6oXajrRteRhwaU", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-minimal", digest: "iYrgj5FAgmujztGZvH5fPK2gu0rzDPJF0Z3CSWallZ0", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-motion-context", digest: "2eNSC6noLNjTP_8f0QwoBCIPwoBAIBlr-gOiRTG0lpw", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-no-time-zone", digest: "7tJhGKGIbj6MVPQ2P4cNI0KN-MLI2MBUk763HC5kkfk", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-recording-device", digest: "IIHNioDM2ZkeqNYCg_8f0HPuPC3b-pPdHziLJEm2j3U", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-study", digest: "sftiHrOuakPAfN5bjto9VoPE7_RpZ1k3YcGDKEqkFDI", assembler: 1, healthKit: 1),
        GoldenRevision("heartbeat-series", digest: "lkN3HRrrJDbWJil2kZg3LKKgmRGyzmEVWgJEugZroEM", assembler: 1, healthKit: 1),
        GoldenRevision("insulin-delivery-bolus", digest: "fCw3-HgNHCW_r1bQ8bY5WiGz52iekzNbJ0-AKZp59yc", assembler: 1, healthKit: 1),
        GoldenRevision("native-identifier-disclosure", digest: "FUSVYtEc61Y5479e6WSJYoDPoJz4x5BRgpp61H0DP0I", assembler: 1, healthKit: 1),
        GoldenRevision("outlines", digest: "dcGlAzsmhgyWChE4Tc78Y_kC0ZQmp5IJ-NKab8fLrZA", assembler: 1, healthKit: 1),
        GoldenRevision("repository-ids-on-every-node", digest: "wnO8sPt82cYYd4m50n4tycbEXWdgvNRlKjQItQI6n4Y", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-blood-pressure", digest: "x4muVgyjqh8AfgVGhaS55MeMVmxJ58UR0hsghhedkEA", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-electrocardiogram", digest: "JJIp4J2S4Vr0CX-d1fi3IqAmyNzuzSz4fyrF-gbrkgM", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-heart-rate-native-identifier", digest: "2nx6odq_wixvjnzRfksJPRgR_UcNs4LkE2l3El_38r4", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-heart-rate", digest: "Bol04wjtd82Dt8GlmFMS84fxEQ6DgPpRsdN-Zd5OA8g", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-workout", digest: "XsaDOMjgcyxDx-jQFZB2bLIcotexSJkELvAPeLOc7Oo", assembler: 1, healthKit: 1),
        GoldenRevision("sleep-analysis", digest: "iNlzbKzQmvuuwSYNtP01iBO0aUf7I6bcRiv7FtZsWx8", assembler: 1, healthKit: 1),
        GoldenRevision("state-of-mind", digest: "tKLQnzIzG1NWFOB2Tlfy4wcZ30_0JzFq4iPyzcLUFXc", assembler: 1, healthKit: 1),
        GoldenRevision("step-count-period", digest: "EGtl-T8Y_4ZYOsQrwTOwooimTqzOPzOizTeh_1xUyuI", assembler: 1, healthKit: 1),
        GoldenRevision("sync-identity", digest: "AVB5QYfWDT4HHvzqxJ7SMeUMLU4miCMWO0m8tjG6Vyg", assembler: 1, healthKit: 1),
        GoldenRevision("two-study-enrollments", digest: "6xtFx6cUROnfra3ZXo_ItI81yhmfSSCsXe9nlJb039A", assembler: 1, healthKit: 1),
        GoldenRevision("udi-disclosure", digest: "U6I4SPk8ZMG1qYnzUpuuXmtZmPJ9bwdCinbmH515Bgw", assembler: 1, healthKit: 1),
        GoldenRevision("workout-route", digest: "qcXsPsBE21qllakPbqcY5JziHqKDqq_Kr5wPgr8ppks", assembler: 1, healthKit: 1),
        GoldenRevision("workout-session", digest: "1JlAdaXFilr2KXrYdxEvZXAGjMUaSxFaJfiPpZuvGlE", assembler: 1, healthKit: 1),
        GoldenRevision("writer-blank-name-with-sync-identity", digest: "eGHwwHdaM8H_QqW2kRQqNcXBj-309dPxpqy3gkXnKNU", assembler: 1, healthKit: 1),
        GoldenRevision("writer-device-classification-without-recording-device", digest: "SnLRcZTmF2g6qdUj-M4UiX6yZGYMavPfLDzJ_3hQPeY", assembler: 1, healthKit: 1),
        GoldenRevision("writer-device-classification", digest: "yZStG8Raudsb--4jeSQkKpkr1ZctGAOJKy81JTmYNMs", assembler: 1, healthKit: 1),
        GoldenRevision("writer-foreign-application", digest: "SaD46SDNVFB6NPQJmIBglAQpwczYwAKlQvSlLl8-d24", assembler: 1, healthKit: 1),
        GoldenRevision("writer-host-equals-converter-host", digest: "fGxbULDNVld5Ke8SXJEiEaHwi_W-3p2KTFpG7i6jQQs", assembler: 1, healthKit: 1),
        GoldenRevision("writer-self-build-equals-revision", digest: "eqwa6qOx48BRIZuR-XapwsKmhNC5G_IaKGtHU_drvVc", assembler: 1, healthKit: 1),
        GoldenRevision("writer-self-older-build", digest: "q59J2fyLBpYqXMqk2gBm1xqXtOmgW3uCHWFMaeQgF5Q", assembler: 1, healthKit: 1),
        GoldenRevision("writer-self-token-identical", digest: "jAlS6dY8iVYxVegEVLk8WC2TOmLam51chxDE7WuWf5k", assembler: 1, healthKit: 1),
        GoldenRevision("writer-without-version", digest: "6cAe98cV6GLI-79ir2LvcG0yd9lT0aHnoz60tvoiW_A", assembler: 1, healthKit: 1)
    ]

    @Test("G17: every golden file has a row, and every row names an existing golden")
    func everyGoldenHasARow() {
        let rows = Set(Self.table.map(\.name))
        #expect(rows.count == Self.table.count, "a golden is named twice")
        let checkedIn = GoldenStore.checkedInNames
        #expect(checkedIn.subtracting(rows).isEmpty, "goldens without a revision row: \(checkedIn.subtracting(rows).sorted())")
        let stale = rows.subtracting(checkedIn).subtracting(GoldenCase.unavailableHere)
        #expect(stale.isEmpty, "rows without a golden: \(stale.sorted())")
    }

    @Test("G17: a golden's bytes match its row, whose revisions the code has reached", arguments: GoldenOutputRevisionTests.table)
    func goldenMatchesItsRevision(_ row: GoldenRevision) throws {
        guard !GoldenCase.unavailableHere.contains(row.name) else {
            return
        }
        let digest = Data(SHA256.hash(data: try GoldenStore.data(named: row.name))).base64URLEncodedStringWithoutPadding
        #expect(digest == row.digest, "\(row.name) changed: update its row with the bumped output revision")
        #expect(row.assembler <= ExchangeGraphAssembler.outputRevision)
        #expect(row.healthKit <= HealthKitAssembly.outputRevision)
    }
}

#endif
