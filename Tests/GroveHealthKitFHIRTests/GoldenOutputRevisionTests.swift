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
        GoldenRevision("bundled-patient-subject", digest: "5iDgaytn2G-8k0wh1P9Q3Ry4jMksyVJ-ayUGBchVbuM", assembler: 1, healthKit: 2),
        GoldenRevision("clinical-document", digest: "1asW-RkPmayr0J1cy__i-SxCb5c64dvfpMYFGkZdsOc", assembler: 1, healthKit: 1),
        GoldenRevision("electrocardiogram-symptom-companion", digest: "EHYE0r3jfMVT2I5fBcnIQaiHnW0oaV_mZh3V12xCWDI", assembler: 1, healthKit: 2),
        GoldenRevision("electrocardiogram-with-symptom", digest: "oUCBD9zurrtjI0O-DbOxhf1Uo_QVwWYGQTt8HloMz9M", assembler: 1, healthKit: 2),
        GoldenRevision("electrocardiogram", digest: "qs8pgYDPAUqNBwnZaUsd3cKARQ-tuJWip2AexfWbMgA", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-clinical-record-dstu2", digest: "9U3i57-PMHal6ADvTYRUUuffIO_5pDB2kB20U_nzX1g", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-clinical-record-r4", digest: "fLwKd9npbWfEncV49t-W0T8TUVGFh5pjZaHMVZfv7kg", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-default-apple-watch-heart-rate", digest: "InGqi5S9GIR-Xqk9CltCUCExrkoBf4tOnBJguLfbVUk", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-default-apple-watch-heart-rate-without-unit-token", digest: "dIRZm-YxyuXejvh3w44cmoYqVIfw2l-cPbmlZon8W-w", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-blood-pressure", digest: "Aq5rL8UXjvLTTQsgor4mTWY-5VIutrJamQ7chv_uRyI", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-electrocardiogram", digest: "3GLqhvS12BlRLJ9ETVd1qV5crlxD8TPRCvCCW1tFDUA", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-electrocardiogram-symptom", digest: "W-CoOf3DL1ofEW_sGj2nCqAi51UX9lV8t70zVrisgdk", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-own-heart-rate", digest: "QtWugQ9lY0GvQ3XF6nidsocOq12Sr4bNwJfqsTQHdXc", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-retraction", digest: "U0OhQ98ldoCEGN0VyAITsm7MXSUoLGSztHpQhRJ2TwQ", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-state-of-mind", digest: "CZ5sA-fjkCqwnp178-8iATtDuHjzGDMxUItbwKHJxxI", assembler: 1, healthKit: 2),
        GoldenRevision("gad7-assessment", digest: "TdgtYWLW0Z6nYvWn6IyNsAssPbn0cuLRlqFng1pOq_c", assembler: 1, healthKit: 2),
        GoldenRevision("gateway-application-role", digest: "z4GLZX9z_-CYLMxzF6l78eLQXXDu_vCV6gHzIRVouYY", assembler: 1, healthKit: 2),
        GoldenRevision("gateway-role", digest: "6cz0Bpd-k9mt_HFFY8xyRT3dkjpDMjI8WnqlyMlGgO8", assembler: 1, healthKit: 2),
        GoldenRevision("heart-rate-device-without-unit-token", digest: "gKIE0MA3n8uoEIiPTWI-TJOBDAD1osZVz6C0sWLibk8", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-interval", digest: "D4QTr9s6IiDjDLGr6Gm41p4QjU8Go6oXajrRteRhwaU", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-minimal", digest: "iYrgj5FAgmujztGZvH5fPK2gu0rzDPJF0Z3CSWallZ0", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-motion-context", digest: "2eNSC6noLNjTP_8f0QwoBCIPwoBAIBlr-gOiRTG0lpw", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-no-time-zone", digest: "7tJhGKGIbj6MVPQ2P4cNI0KN-MLI2MBUk763HC5kkfk", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-recording-device", digest: "IIHNioDM2ZkeqNYCg_8f0HPuPC3b-pPdHziLJEm2j3U", assembler: 1, healthKit: 1),
        GoldenRevision("heart-rate-study", digest: "sftiHrOuakPAfN5bjto9VoPE7_RpZ1k3YcGDKEqkFDI", assembler: 1, healthKit: 1),
        GoldenRevision("heartbeat-series", digest: "fB3bdqSnBH2vJxBfzQQDFFeItPoT6Bs8Yom7uFbYS98", assembler: 1, healthKit: 2),
        GoldenRevision("insulin-delivery-bolus", digest: "fCw3-HgNHCW_r1bQ8bY5WiGz52iekzNbJ0-AKZp59yc", assembler: 1, healthKit: 1),
        GoldenRevision("native-identifier-disclosure", digest: "d0cEPkdGfs7W8CYbUpS-GDKoc64jN21WjgkWSibIAAM", assembler: 1, healthKit: 2),
        GoldenRevision("outlines", digest: "SWyFVDm2r7z4Yqp6Y36Oub3aNtT6zO8emIKx-J5qmNs", assembler: 1, healthKit: 2),
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
        GoldenRevision("two-study-enrollments", digest: "_LQH7q4xMKuGfcWl6_Ad65hcTU6PDJ_C_Xd31ZGD0HQ", assembler: 1, healthKit: 2),
        GoldenRevision("udi-disclosure", digest: "WzH-xG6V54w8RejhkvpOo7L__Xi3J6qZc1giw8-ps4M", assembler: 1, healthKit: 2),
        GoldenRevision("workout-route", digest: "PBv3pI8sKIsHZAKmYK_9eTawK56ITbaCGS2miDe0Cxc", assembler: 1, healthKit: 2),
        GoldenRevision("workout-session", digest: "1JlAdaXFilr2KXrYdxEvZXAGjMUaSxFaJfiPpZuvGlE", assembler: 1, healthKit: 1),
        GoldenRevision("workout-session-context", digest: "EvoLNOTHZrUcHlEFwZDa-ZJr5HyW-iB9C4pgyOb_S8E", assembler: 1, healthKit: 2),
        GoldenRevision("writer-blank-name-with-sync-identity", digest: "eGHwwHdaM8H_QqW2kRQqNcXBj-309dPxpqy3gkXnKNU", assembler: 1, healthKit: 1),
        GoldenRevision("writer-foreign-application", digest: "SaD46SDNVFB6NPQJmIBglAQpwczYwAKlQvSlLl8-d24", assembler: 1, healthKit: 1),
        GoldenRevision("writer-host-equals-converter-host", digest: "fGxbULDNVld5Ke8SXJEiEaHwi_W-3p2KTFpG7i6jQQs", assembler: 1, healthKit: 1),
        GoldenRevision("writer-non-ascii-name", digest: "J4HDch8QfPqlqhtpYfzk7ai7RSHMFIzq4LysSa-BYc4", assembler: 1, healthKit: 2),
        GoldenRevision("writer-omitted-without-recording-device", digest: "SnLRcZTmF2g6qdUj-M4UiX6yZGYMavPfLDzJ_3hQPeY", assembler: 1, healthKit: 1),
        GoldenRevision("writer-omitted", digest: "eJqZQLyxYaLExf9ESiJxNRcvk6pO9_9vyX3ZBlqU5OU", assembler: 1, healthKit: 2),
        GoldenRevision("writer-self-build-equals-revision", digest: "eqwa6qOx48BRIZuR-XapwsKmhNC5G_IaKGtHU_drvVc", assembler: 1, healthKit: 1),
        GoldenRevision("writer-self-older-build", digest: "q59J2fyLBpYqXMqk2gBm1xqXtOmgW3uCHWFMaeQgF5Q", assembler: 1, healthKit: 1),
        GoldenRevision("writer-self-token-identical", digest: "jAlS6dY8iVYxVegEVLk8WC2TOmLam51chxDE7WuWf5k", assembler: 1, healthKit: 1),
        GoldenRevision("writer-without-version", digest: "6cAe98cV6GLI-79ir2LvcG0yd9lT0aHnoz60tvoiW_A", assembler: 1, healthKit: 1)
    ]

    @Test("G17: every golden file has a row, and every row names an existing golden")
    func everyGoldenHasARow() {
        let rows = Set(Self.table.map(\.name))
        #expect(rows.count == Self.table.count, "a golden is named twice")
        let checkedIn = GoldenStore.resources.names(withExtension: "json")
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
