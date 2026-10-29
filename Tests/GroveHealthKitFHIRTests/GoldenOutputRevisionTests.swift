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


/// One checked-in golden file or the content corpus, its SHA-256 (base64url without padding), and the output
/// revisions an output it pins last changed under.
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
/// any change that alters a golden or a content-corpus output must bump `ExchangeGraphAssembler.outputRevision` or
/// `HealthKitAssembly.outputRevision`. This table pins every golden file's digest, and ``contentCorpus`` the
/// corpus's: a changed file fails here until its row is updated, and the updated row must carry the bumped revision
/// when an output changed, which review checks in the diff. A row never names a revision the code has not reached.
/// A new golden adds a row without a bump, and so does a golden whose case changed its inputs while the output for
/// equal inputs stayed the same; a corpus that only gains vectors, or renders equal outputs another way, updates its
/// digest without a bump.
@Suite
struct GoldenOutputRevisionTests {
    static let table: [GoldenRevision] = [
        GoldenRevision("blood-pressure-correlation", digest: "Ugah-6eXCUS9EkjhDC2FZQ13WjfqeND-6hlzoaiU_HM", assembler: 1, healthKit: 15),
        GoldenRevision("blood-pressure-member-metadata", digest: "Cn0UpEQOtIWA3H7_mufK4HOeRV-ySGIqyAXbfRE_vYM", assembler: 1, healthKit: 15),
        GoldenRevision("body-fat-percentage-fraction", digest: "cUVavPGB-yrwxr2lYmoC8wPiuQk5lBdjTWiNDsdoVXI", assembler: 1, healthKit: 15),
        GoldenRevision("body-mass-user-entered", digest: "-xBPC-M9RbWCKHeX_UUazr8HwoZiCaf9N-gTRJN1N-s", assembler: 1, healthKit: 15),
        GoldenRevision("bundled-patient-subject", digest: "ZL1WXYisQ7TZxoeQ5DhD7_3VYvlwsDeF7Ul8zF04CcY", assembler: 1, healthKit: 15),
        GoldenRevision("clinical-document", digest: "ThgTRu-qfEtK5IuJbOmhktZ1dH4zHrHFv18zIHc2Dxw", assembler: 1, healthKit: 15),
        GoldenRevision("electrocardiogram-symptom-companion", digest: "z26WsI8NEKUFdnMx-eKQzqWFwgs0N9ehWEHQxyEfHow", assembler: 1, healthKit: 15),
        GoldenRevision("electrocardiogram-with-symptom", digest: "gfk2cARfiqLHmkctOEjoBRJRnqWS4AzjKJcoE8vKSUc", assembler: 1, healthKit: 15),
        GoldenRevision("electrocardiogram", digest: "gU0D6g7qXluXploBYwIJVP0svrLmneA339b-OBX1HGE", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-clinical-record-dstu2", digest: "3_10kyCDnXOzOI50ozg0E5UOAdrtoqJmDgVgqqsf740", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-clinical-record-r4", digest: "zwko977-YJ7gfUUJ8KPdo77YKxH-41XiIlcY3SZUEmM", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-default-apple-watch-heart-rate", digest: "E9iO-H0JWtp0dPqTbhoyLrA6V3gKehjktYtqR46vbfo", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-default-apple-watch-heart-rate-without-unit-token", digest: "Z0bPlx97OlrBV6X3UL9RGnsk8LOo7l2w6xcIAX_vlck", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-deployment-blood-pressure", digest: "aYlaX3U_L7u0aR0kno7OlQGf8NYAM8FvoymhoDuJi28", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-deployment-electrocardiogram", digest: "bnJmlf8K8oE4AamSWKyQXOVdgOWkprW1UgIiM0lbzhE", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-deployment-electrocardiogram-symptom", digest: "urdB2kblWuSQ01lfa399p-hhe0u9V-BpwSBqj-FdQAE", assembler: 1, healthKit: 15),
        GoldenRevision("exporter-deployment-own-heart-rate", digest: "Bhep60lfUbw4c5CgJxHSvLC1EAKbJSaFSN_7JsNYnxw", assembler: 1, healthKit: 14),
        GoldenRevision("exporter-deployment-retraction", digest: "U0OhQ98ldoCEGN0VyAITsm7MXSUoLGSztHpQhRJ2TwQ", assembler: 1, healthKit: 2),
        GoldenRevision("exporter-deployment-state-of-mind", digest: "IXu3LHFveoGUrmjZikqivJyT32FJm_InR2pUNhG8GQc", assembler: 1, healthKit: 15),
        GoldenRevision("gad7-assessment", digest: "2tcY475qjtLXiKD3d5ngYjb_VcyAdlfpcOnoGXQKj50", assembler: 1, healthKit: 15),
        GoldenRevision("gateway-application-role", digest: "SWfkQRo31VXtxZmXto1ydCRSQI-TOvwb5JHidAr95gQ", assembler: 1, healthKit: 15),
        GoldenRevision("gateway-role", digest: "J7ep-LfjxCSlivOpXyw-_LZHK29WhiNHLYsggDii4DE", assembler: 1, healthKit: 15),
        GoldenRevision("guide-example-heart-rate", digest: "JSlBfropNmPCBkIA6oDXr8w8XIbf4zYpMC0P_NK9zZo", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-device-without-unit-token", digest: "Tpybaws2jgKE626AyK_J1X5E3rAhLCKfKIWM4Wv-LtE", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-interval", digest: "oUNEBnN9EIRLLPhJONY_USdaK27n44VbbPIeXuFVu9g", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-minimal", digest: "pb4xOsv9WQqP23LwrzbDkoVNc1dUqg9QZCm4Op77fdw", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-motion-context", digest: "JmM6dAYTWmeJsHJXesejnGRToZcXKrH_SF4gYFOGr-g", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-no-time-zone", digest: "gQKyTv8BrwCxQ7Y4_MzTl6Vnu4PRUl6sjOWGE0S7Oe8", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-recording-device", digest: "v-kuPnMJ7xs9fmihwZ4fibIEYq56Lxag0VvxFmVlSas", assembler: 1, healthKit: 15),
        GoldenRevision("heart-rate-study", digest: "UuL3--DImZUA5DBiC_2Cu_RFwzcwp8DLWKYfmDnzDnc", assembler: 1, healthKit: 15),
        GoldenRevision("heartbeat-series", digest: "xreIO2fxIe_CjT9C8s9Qtezlq3-UXj3tGIq8yr07blk", assembler: 1, healthKit: 15),
        GoldenRevision("high-heart-rate-threshold", digest: "cWUiAW1PvdZYPxyRUf9aVycunYrg_yxVhJkYIfRmNMs", assembler: 1, healthKit: 16),
        GoldenRevision("insulin-delivery-bolus", digest: "R8yU3lrWsgJLI5F5S77onqZ7xEolIhlKdunbaVdAZiU", assembler: 1, healthKit: 15),
        GoldenRevision("native-identifier-disclosure", digest: "jxC3bnInVPTCS7fo985UkoivoSwo0VDa2JF3F1Kk6sQ", assembler: 1, healthKit: 15),
        GoldenRevision("outlines", digest: "cRm98HOWfIsQdIOAcNCsy_Ah628VkSXCEBWpNRprLzE", assembler: 1, healthKit: 16),
        GoldenRevision("retraction-blood-pressure", digest: "x4muVgyjqh8AfgVGhaS55MeMVmxJ58UR0hsghhedkEA", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-electrocardiogram", digest: "K6KSuYLUUK8MtIKDYjC12GUYxMRLxKcQ_qm2RP6DdiQ", assembler: 1, healthKit: 17),
        GoldenRevision("retraction-heart-rate-native-identifier", digest: "2nx6odq_wixvjnzRfksJPRgR_UcNs4LkE2l3El_38r4", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-heart-rate", digest: "CiMnTaKtIFKsw99cXYpfbCjsAmmhKCcK3gJU93TXyl4", assembler: 1, healthKit: 1),
        GoldenRevision("retraction-workout", digest: "ISgTtrgL64U1DEutQ7RDcrq0TKfLtGnM2yL-qupINgU", assembler: 1, healthKit: 17),
        GoldenRevision("sleep-analysis", digest: "SOmhLTvljdkhjdCvJNchmoYN_M6Oj2wbj3vkD-Hkveo", assembler: 1, healthKit: 15),
        GoldenRevision("state-of-mind", digest: "XoTiLzwRBW8gHDQ7sh7o1lC7K7wKv9R9oQirMoJM8Ds", assembler: 1, healthKit: 15),
        GoldenRevision("step-count-period", digest: "wpYjZ92PoHXI9ngL4cvbtkZ2aarucnQWZfHcfI0XpW0", assembler: 1, healthKit: 15),
        GoldenRevision("sync-identity", digest: "-cUH6E1XhDGgZZ1USKLkwRhlTJ6zM3_lAv7sMwuWncI", assembler: 1, healthKit: 14),
        GoldenRevision("two-study-enrollments", digest: "RuP2sdOmKtpl4KiklO-BJEqZ0SSAkicO3FnBN5EOoTo", assembler: 1, healthKit: 15),
        GoldenRevision("udi-disclosure", digest: "Of8xURSmhS7NCWyOBgTfvl0-jOGKHewGj_J-0S4qUBU", assembler: 1, healthKit: 15),
        GoldenRevision("walking-steadiness-notification", digest: "4GDfcRlqW7iWMWgzyRoYUBngUiO3SzwxK73_ZqbTiV8", assembler: 1, healthKit: 15),
        GoldenRevision("workout-route", digest: "pStwosZN1HtBQsuu2EICXhNSHOeyBmTIebjh8KGhu1g", assembler: 1, healthKit: 15),
        GoldenRevision("workout-session", digest: "tejX1Pfk_LGRrXWm5TNrqd9hUzSl4dKLV62bDdMkotU", assembler: 1, healthKit: 15),
        GoldenRevision("workout-session-context", digest: "WD7uThlrnfW3z9oXs3i0dtB0nMs5EFuj6Z76VzPSx6A", assembler: 1, healthKit: 15),
        GoldenRevision("writer-blank-name-with-sync-identity", digest: "J4jTxgQjwtk72DWzmiIEYpbbS9JnooGXZTAQn5N6HJU", assembler: 1, healthKit: 15),
        GoldenRevision("writer-foreign-application", digest: "3tZGg1hKs5Mr4EwoTa1Bo3DuMIJ7yxaMFDoGHWh21bk", assembler: 1, healthKit: 14),
        GoldenRevision("writer-host-equals-converter-host", digest: "sx9ApJAu_tnYMwa_DtLm2yxbVVdefwA7xnsTulRwhZE", assembler: 1, healthKit: 14),
        GoldenRevision("writer-non-ascii-name", digest: "2fy1oMLi5R3ZuQqdqkv9gdnqKxLHXGNS-iTJYbE1AGc", assembler: 1, healthKit: 14),
        GoldenRevision("writer-omitted-without-recording-device", digest: "08eEVSBejxzo54rCoCvTu1uQjVmBc8Hj_pEtH6oh0pg", assembler: 1, healthKit: 15),
        GoldenRevision("writer-omitted", digest: "0Pb5qqZ5ZRuk_S8Q6xAFONvyH8mxrigUwWrUQoAr54k", assembler: 1, healthKit: 15),
        GoldenRevision("writer-self-build-equals-revision", digest: "MF81VpXuV9wV1743A6oEavSrUgXnp311r12IZSoXaMA", assembler: 1, healthKit: 14),
        GoldenRevision("writer-self-older-build", digest: "n03mwTc2Z4Uamn-mhB8KOxH0FjkR_RoX9lpOJKowEkw", assembler: 1, healthKit: 14),
        GoldenRevision("writer-self-token-identical", digest: "9JS5Fkj-UMSloBBRpt5sWQFsElqFdoQydeIYZmpu__I", assembler: 1, healthKit: 14),
        GoldenRevision("writer-without-version", digest: "6cAe98cV6GLI-79ir2LvcG0yd9lT0aHnoz60tvoiW_A", assembler: 1, healthKit: 1)
    ]

    /// The content corpus pins the content layer's output, refusals included, for every vector, so a changed output
    /// bumps a revision as a changed golden does, even where no golden changes.
    static let contentCorpus = GoldenRevision("content-corpus", digest: "VWow6tdSMbfGSR5LU2iOpLUMHSWC91FQZuZqEgP4w3o", assembler: 1, healthKit: 15)

    /// Expects `data` to hash to `row`'s digest, and `row` to name revisions the code has reached.
    private static func expect(_ row: GoldenRevision, matches data: Data) {
        let digest = Data(SHA256.hash(data: data)).base64URLEncodedStringWithoutPadding
        #expect(digest == row.digest, "\(row.name) changed: update its row, with the bumped output revision if an output changed")
        #expect(row.assembler <= ExchangeGraphAssembler.outputRevision)
        #expect(row.healthKit <= HealthKitAssembly.outputRevision)
    }

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
        Self.expect(row, matches: try GoldenStore.data(named: row.name))
    }

    @Test("G17: the content corpus's bytes match its row, whose revisions the code has reached")
    func contentCorpusMatchesItsRevision() throws {
        Self.expect(Self.contentCorpus, matches: try ContentCorpusStore.checkedIn())
    }
}

#endif
