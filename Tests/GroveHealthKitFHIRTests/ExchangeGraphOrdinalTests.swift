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


/// Pins the ordinal refusal without the shared corpus: the digest covers the ordinal the key
/// itself states, so a key minted at the wrong ordinal verifies against its own claim.
@Suite
struct ExchangeGraphOrdinalTests {
    @Test("A self-consistent key minted at the wrong per-role ordinal is refused")
    func misnumberedEntryNodeOrdinalIsRefused() throws {
        let timestamp = Date(timeIntervalSince1970: 1_787_148_600)
        let context = HealthKitConversionContext(
            subject: .testPatient,
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
        let conversion = try HealthKitConverter().convert(
            HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
                start: timestamp,
                end: timestamp.addingTimeInterval(60)
            ),
            context: context
        )
        let misnumbered = try ExchangeNodeKey(
            system: context.entryNodeIdentifierSystem,
            eventIdentifier: context.eventIdentifier,
            nodeRole: "conversion-provenance",
            ordinal: 1
        )
        // The mint is genuine, so nothing but the ordinal itself is out of place.
        #expect(try ExchangeNodeKey(
            misnumbered.identifier,
            eventIdentifier: context.eventIdentifier
        ).ordinal == misnumbered.ordinal)

        var bundle = conversion.bundle
        var entries = try #require(bundle.entry)
        let index = try #require(entries.firstIndex { entry in
            if case .provenance = entry.resource {
                return true
            }
            return false
        })
        entries[index] = try ExchangeIdentity.entry(
            nodeKey: misnumbered,
            resource: #require(entries[index].resource)
        )
        bundle.entry = entries

        #expect(throws: ExchangeGraphError.ruleViolation(.entryNodeOrdinal)) {
            try ExchangeGraph(
                kind: .active,
                eventIdentifier: conversion.graph.eventIdentifier,
                bundle: bundle
            )
        }
    }
}

#endif
