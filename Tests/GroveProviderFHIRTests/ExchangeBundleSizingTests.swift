//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveProviderFHIR
import Testing


@Suite
struct ExchangeBundleSizingTests {
    @Test("Exact batch sizing includes shared-node deduplication and escaped transport identifiers")
    func incrementalSize() throws {
        let context = try WithingsFHIRTests.context()
        var packer = ExchangeBundlePacker(kind: .active)
        let transport = try BusinessIdentifier(system: "https://study.example.org/transport", value: "delivery-\"\\é")
        for index in 0..<5 {
            let results = try WithingsFHIR.convert(
                .init(id: "group-\(index)", date: WithingsFHIRTests.date, measures: [.init(type: 1, value: 70, unit: 0)]),
                context: context
            )
            let record = try #require(results.first?.record)
            #expect(try packer.insert(record) == .inserted)
            for identifier in [nil, transport] {
                let size = try packer.bundleByteCount(packedAt: context.instant, transportIdentifier: identifier)
                let graph = try packer.bundle(packedAt: context.instant, transportIdentifier: identifier)
                #expect(size == graph.json.count)
            }
            let beforeDuplicate = try packer.bundleByteCount(packedAt: context.instant)
            #expect(try packer.insert(record) == .duplicate)
            #expect(try packer.bundleByteCount(packedAt: context.instant) == beforeDuplicate)
        }
    }
}
