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
import HealthKit
import Testing


/// Invariant checks over one conversion, shared by the corpus pass so no vector converts twice.
enum ContentCorpusInvariants {
    /// Every output a conversion of `source` emitted that its source type's catalog outputs do not name, and a
    /// primary output that is not the catalog's first: identity enters only through the catalog's (role,
    /// discriminator) pairs, minted under the context the vector converted under.
    static func uncatalogedOutputs(of outcome: ContentCorpusRecorder.Outcome, source: ContentCorpusSource) throws -> [String] {
        guard case .converted(let set) = outcome else {
            return []
        }
        let context = try ContentCorpusRecorder.context(for: source)
        return try set.all.flatMap { conversion -> [String] in
            let record = try context.identityScope.sourceRecord(
                adapterID: HealthKitConverter.adapterID,
                sourceType: conversion.source.type.rawValue,
                repositoryScope: context.event.repositoryScope,
                nativeRecordID: conversion.source.uuid.uuidString.lowercased()
            )
            let cataloged = try HealthKitCatalog.outputs(for: conversion.source.type).map { output in
                try record.output(role: output.role, discriminator: output.discriminator)
            }
            let emitted = [conversion.identifiers.primaryOutput] + conversion.identifiers.childOutputs
            var problems = emitted.filter { !cataloged.contains($0) }.map { "\($0.identifier.value) is not a cataloged output" }
            if cataloged.first != conversion.identifiers.primaryOutput {
                problems.append("the primary output is not the catalog's first")
            }
            return problems
        }
    }
}


/// The content layer's permanent invariants (oracle O6) as today's public surface states them: rule-table totality,
/// unit compatibility, the reverse map as the inverse of the forward bindings, and corpus coverage of every row.
/// (Every emitted output being cataloged runs over the whole corpus in `ContentCorpusTests`; determinism is the
/// corpus reproducing across processes; Mobile milliseconds rounding from 1970 is `HealthKitEffectiveTimeTests`.)
@Suite
struct ContentInvariantTests {
    /// Supported rows the adapter does not convert yet: food, the audiogram, and five characteristics.
    private static let notYetConvertible: Set<String> = [
        "HKCorrelationTypeIdentifierFood", "HKDataTypeIdentifierAudiogram", "HKCharacteristicTypeIdentifierBiologicalSex",
        "HKCharacteristicTypeIdentifierBloodType", "HKCharacteristicTypeIdentifierDateOfBirth",
        "HKCharacteristicTypeIdentifierFitzpatrickSkinType", "HKCharacteristicTypeIdentifierWheelchairUse"
    ]

    /// Platform-exclusive rows the adapter carries as recording documents: the heartbeat series, the workout route,
    /// CDA documents and the nine clinical record types.
    private static let platformDocuments: Set<String> = Set(ContentCorpusGrid.rows(prefix: "HKClinicalTypeIdentifier").map(\.sourceTypeIdentifier))
        .union([HKDataTypeIdentifierHeartbeatSeries, HKWorkoutRouteTypeIdentifier, "HKDocumentTypeIdentifierCDA"])

    /// Rows that name no sample type, so no conversion can feed them.
    private static let notSampleTypes: Set<String> = Set(ContentCorpusGrid.rows(prefix: "HKCharacteristicTypeIdentifier").map(\.sourceTypeIdentifier))
        .union(["HKDataTypeUserAnnotatedMedicationConcept"])

    /// Every generated measurement contract by id, the first catalog winning; unlike the corpus grid's, it follows
    /// the catalogs wherever they go.
    private static let contracts: [String: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).map { ($0.id, $0) }
    ) { first, _ in first }

    /// Quantity rows that convert in a published unit binding: each one's unit measures its type.
    private static var boundQuantityRows: [(row: HealthKitContractRow, unit: HKUnit)] {
        ContentCorpusGrid.rows(prefix: "HKQuantityTypeIdentifier").compactMap { row in
            guard row.implementationStatus == .supported,
                  let type = HealthKitSourceType(rawValue: row.sourceTypeIdentifier),
                  !HealthKitCatalog.outputs(for: type).isEmpty,
                  let code = row.measurementIDs.first.flatMap({ contracts[$0] })?.quantity?.code,
                  let unit = HealthKitCatalog.unit(forUCUMCode: code) else {
                return nil
            }
            return (row, unit)
        }
    }

    @Test("Every supported row mints outputs except the declared not-yet set; only platform-exclusive documents mint any otherwise")
    func ruleTableIsTotal() throws {
        var unconverted: Set<String> = []
        var documents: Set<String> = []
        for row in HealthKitContract.rows {
            let type = try #require(HealthKitSourceType(rawValue: row.sourceTypeIdentifier))
            let outputs = HealthKitCatalog.outputs(for: type)
            switch row.implementationStatus {
            case .supported where outputs.isEmpty:
                unconverted.insert(row.sourceTypeIdentifier)
            case .platformExclusive where !outputs.isEmpty:
                documents.insert(row.sourceTypeIdentifier)
                #expect(outputs.map(\.resourceType) == [.documentReference], "\(row.sourceTypeIdentifier) mints \(outputs)")
            case .intentionallyUnsupported:
                #expect(outputs.isEmpty, "\(row.sourceTypeIdentifier) is intentionally unsupported but mints outputs")
            default:
                break
            }
        }
        #expect(unconverted == Self.notYetConvertible)
        #expect(documents == Self.platformDocuments)
    }

    @Test("Every bound quantity unit measures its source type, and both lookups of every binding agree")
    func quantityUnitsAreCompatible() throws {
        let bound = Self.boundQuantityRows
        for (row, unit) in bound {
            let type = try #require(HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: row.sourceTypeIdentifier)))
            #expect(type.is(compatibleWith: unit), "\(row.sourceTypeIdentifier) cannot be read in \(unit.unitString)")
        }
        // The 108 unit-read quantity rows, less body-mass index, whose contract no generated catalog carries yet. M1
        // (generator G3) generates it; should it join a catalog's `all`, this count becomes 108 (see ContentCorpusGrid).
        #expect(bound.count == 107, "\(bound.count) quantity rows convert through a unit binding")
        for binding in HealthKitCatalog.unitBindings {
            let byCode = try #require(HealthKitCatalog.unit(forUCUMCode: binding.ucumCode))
            let bySpelling = try #require(HealthKitCatalog.unit(forUnitSpelling: binding.displayUnit))
            #expect(HKQuantity(unit: binding.unit, doubleValue: 1).is(compatibleWith: byCode), "\(binding.ucumCode)")
            #expect(HKQuantity(unit: binding.unit, doubleValue: 1).is(compatibleWith: bySpelling), "\(binding.displayUnit)")
        }
    }

    @Test("The reverse map lands each measurement on the one quantity type that converts into it, and refuses the rest")
    func reverseMapInvertsTheForwardBindings() throws {
        var forward: [String: [String]] = [:]
        for (row, _) in Self.boundQuantityRows {
            if let id = row.measurementIDs.first {
                forward[id, default: []].append(row.sourceTypeIdentifier)
            }
        }
        var mismatches: [String] = []
        for contract in MeasurementCatalog.all + HealthKitMeasurementCatalog.all {
            // Today's map, read without building a sample: HealthKit raises on samples it refuses to create.
            let projected = (try? HealthKitSampleProjection.quantityTypeIdentifier(for: contract.id))?.rawValue
            let expected = forward[contract.id].flatMap { $0.count == 1 ? $0.first : nil }
            if projected != expected {
                mismatches.append("\(contract.id): \(projected ?? "refused") != \(expected ?? "refused")")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(forward.values.contains { $0.count > 1 }, "some measurement is bound to several types and must refuse")
    }

    @Test("Every row that names a sample type has a corpus vector converting it")
    func everySampleRowIsInTheCorpus() {
        let converted = Set(ContentCorpusGrid.vectors.compactMap { vector -> String? in
            guard case .convert(let source) = vector.input else {
                return nil
            }
            return source.record.sourceTypeIdentifier
        })
        let missing = Set(HealthKitContract.rows.map(\.sourceTypeIdentifier)).subtracting(Self.notSampleTypes).subtracting(converted)
        #expect(missing.isEmpty, "rows without a conversion vector: \(missing.sorted())")
    }
}


extension ContentCorpusRecord {
    /// The source type a record of this payload converts as.
    var sourceTypeIdentifier: String {
        switch self {
        case .quantity(let type, _, _), .category(let type, _), .correlation(let type, _), .assessment(let type, _),
             .clinicalRecord(let type, _, _), .bare(let type, _):
            type
        case .workout: HKWorkoutTypeIdentifier
        case .stateOfMind: HKSampleType.stateOfMindType().identifier
        case .electrocardiogram: HKObjectType.electrocardiogramType().identifier
        case .heartbeatSeries: HKDataTypeIdentifierHeartbeatSeries
        case .workoutRoute: HKWorkoutRouteTypeIdentifier
        case .cdaDocument: "HKDocumentTypeIdentifierCDA"
        }
    }
}

#endif
