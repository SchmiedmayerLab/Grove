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
import ModelsR4
import Testing


/// A measurement contract with every field the content compiler reads editable.
struct ContractDraft {
    /// The contract the draft starts from.
    private let base: MeasurementContract
    /// The measurement code.
    var code: CodingContract
    /// The value quantity.
    var quantity: QuantityContract?
    /// The components.
    var components: [ComponentContract]
    /// The CodeSystem of the coded results.
    var resultCodeSystem: String?
    /// The codes the contract admits without publishing them.
    var allowedValues: [String]
    /// The published result codes.
    var resultCodes: [ResultCodeContract]

    /// The contract as drafted.
    var contract: MeasurementContract {
        MeasurementContract(
            id: base.id,
            profile: base.profile,
            code: code,
            requiredCodings: base.requiredCodings,
            quantity: quantity,
            components: components,
            resultCodeSystem: resultCodeSystem,
            allowedValues: allowedValues,
            resultCodes: resultCodes,
            method: base.method,
            methodChoice: base.methodChoice,
            effective: base.effective,
            category: base.category
        )
    }

    /// A draft of `base`.
    init(_ base: MeasurementContract) {
        self.base = base
        code = base.code
        quantity = base.quantity
        components = base.components
        resultCodeSystem = base.resultCodeSystem
        allowedValues = base.allowedValues
        resultCodes = base.resultCodes
    }

    /// Changes the component `id` as `change` says, or drops it when `change` returns `nil`.
    mutating func component(_ id: String, _ change: (ComponentContract) -> ComponentContract?) {
        components = components.compactMap { $0.id == id ? change($0) : $0 }
    }
}


/// The plan compiler's defect policy (oracle O6), fed rules and contracts that do not fit: it never traps. A rule its
/// contract cannot satisfy refuses the whole type as not yet convertible and names the mismatch; a coded value whose
/// code the contract does not admit stays unresolved while the type's other values convert; a type the inventory
/// converts but no rule covers is refused as today and named.
@Suite
struct HealthKitContentCompilerTests {
    @Test("A row whose measurement has no generated contract refuses its type and names the row")
    func missingContractRefusesTheType() {
        var contracts = HealthKitContentCompiler.generatedContracts
        contracts[MeasurementCatalog.heartRate.id] = nil
        let compilation = HealthKitContentCompiler.compile(contracts: contracts)
        Self.expectRefused(.heartRate, "names no generated measurement contract", in: compilation)
    }

    @Test("A contract without the code display, quantity, unit, CodeSystem or result its rule reads refuses its type")
    func contractMismatchesRefuseTheType() throws {
        try Self.expectRefused(.heartRate, "states no display for code 0000-0") { draft in
            draft.code = CodingContract(system: "http://loinc.org", code: "0000-0")
        }
        try Self.expectRefused(.heartRate, "states no quantity") { $0.quantity = nil }
        try Self.expectRefused(.heartRate, "reads [furlong], which has no HealthKit unit") { draft in
            draft.quantity = QuantityContract(system: "http://unitsofmeasure.org", code: "[furlong]", unit: "furlong")
        }
        try Self.expectRefused(.mindfulSession, "states its duration in h, neither seconds nor minutes") { draft in
            draft.quantity = QuantityContract(system: "http://unitsofmeasure.org", code: "h", unit: "h")
        }
        try Self.expectRefused(.acne, "states no result CodeSystem") { $0.resultCodeSystem = nil }
        try Self.expectRefused(.lactation, "states no result code for the occurrence") { $0.resultCodes = [] }
        try Self.expectRefused(.sexualActivity, "admits no result code protected") { draft in
            draft.resultCodes.removeAll { $0.code == "protected" }
        }
    }

    @Test("A contract without a component its rule reads, or with one no member states, refuses its type")
    func componentMismatchesRefuseTheType() throws {
        try Self.expectRefused(.bloodPressure, "states no components") { $0.components = [] }
        try Self.expectRefused(.bloodPressure, "states component mean, which no correlation member states") { draft in
            draft.component("systolic") { $0.with(id: "mean") }
        }
        try Self.expectRefused(.bloodPressure, "reads kPa, which has no HealthKit unit") { draft in
            let kilopascal = QuantityContract(system: "http://unitsofmeasure.org", code: "kPa", unit: "kPa")
            draft.component("diastolic") { $0.with(quantity: kilopascal) }
        }
        try Self.expectRefused(.menstrualFlow, "states no coded cycleStart component") { $0.components = [] }
        try Self.expectRefused(.workout, "states no quantity component heart-rate-max") { $0.component("heart-rate-max") { _ in nil } }
        try Self.expectRefused(.stateOfMind, "states no coded component label") { $0.component("label") { _ in nil } }
    }

    @Test("A hand-written workout or State of Mind code the contract does not admit refuses its type")
    func unadmittedCodesRefuseTheType() throws {
        let workoutSystem = try #require(MeasurementCatalog.workout.resultCodeSystem)
        try Self.expectRefused(.workout, "admits no code yoga in \(workoutSystem)") { $0.allowedValues.removeAll { $0 == "yoga" } }
        let labels = try #require(HealthKitMeasurementCatalog.stateOfMind.components.first { $0.id == "label" }?.resultCodeSystem)
        try Self.expectRefused(.stateOfMind, "admits no code happy in \(labels)") { draft in
            draft.component("label") { $0.with { $0.code != "happy" } }
        }
    }

    @Test("A literal category code the contract does not admit leaves that value unresolved and the others converting")
    func unadmittedLiteralCodeIsUnresolved() throws {
        let mild = HKCategoryValueSeverity.mild.rawValue
        let compilation = try Self.compile(.acne) { $0.allowedValues.removeAll { $0 == "mild" } }
        let defect = "\(HealthKitSourceType.acne.rawValue): value \(mild) reports as mild, which the contract does not admit"
        #expect(Self.ownDefects(of: compilation) == [defect])
        guard case .observation(let observation)? = compilation.byIdentifier[HealthKitSourceType.acne.rawValue]?.route,
              case let .coded(values, unresolved) = observation.value else {
            Issue.record("Acne no longer converts through its coded values")
            return
        }
        #expect(unresolved == [mild])
        #expect(Set(values.keys) == Set(CodedTable.severity.rows.map { $0.raw }).subtracting([mild]))
    }

    @Test("A type listed twice, or a table mapping one value twice, refuses its type")
    func doubleListingsRefuseTheType() throws {
        let twice = HealthKitContentRules.groups + [HealthKitContentRules.RuleGroup(.observation(.occurrence), [.lactation])]
        Self.expectRefused(.lactation, "is listed under more than one rule", in: HealthKitContentCompiler.compile(groups: twice))
        let unspecified = CodedTable.Row("change-unspecified")
        // Key-value pairs keep both spellings of the one value.
        let rows: KeyValuePairs<HKCategoryValueAppetiteChanges, CodedTable.Row> = [.unspecified: unspecified, HKCategoryValueAppetiteChanges.unspecified: unspecified]
        let table = CodedTable(HKCategoryValueAppetiteChanges.self, sourceSystem: nil, rows: rows)
        let remapped = HealthKitContentRules.RuleGroup(.observation(.coded(table)), [.appetiteChanges])
        let groups = Self.groups(without: .appetiteChanges) + [remapped]
        Self.expectRefused(.appetiteChanges, "maps value 0 twice", in: HealthKitContentCompiler.compile(groups: groups))
    }

    @Test("A row the inventory converts but no rule covers is refused for what its row admits, and named")
    func missingRulesAreNamed() {
        for type in [HealthKitSourceType.heartbeatSeries, .cda, .coverageRecord] {
            let compilation = HealthKitContentCompiler.compile(groups: Self.groups(without: type))
            Self.expectRefused(type, "claims a document profile, but has no rule", in: compilation, as: .platformExclusiveSourceType(type))
        }
        let compilation = HealthKitContentCompiler.compile(groups: Self.groups(without: .sexualActivity))
        let defect = "supported, but has no rule and is not declared not yet convertible"
        Self.expectRefused(.sexualActivity, defect, in: compilation)
    }
}


extension HealthKitContentCompilerTests {
    /// The defects `compilation` names beyond the adapter's own compilation's: a defect in the real rules or
    /// contracts fails the tests that pin those (`HealthKitContentPlanTests`), never these.
    private static func ownDefects(of compilation: HealthKitContentCompiler.Compilation) -> [String] {
        compilation.defects.filter { !HealthKitContentPlan.compileDefects.contains($0) }
    }

    /// The adapter's rule groups without the one listing `type`.
    private static func groups(without type: HealthKitSourceType) -> [HealthKitContentRules.RuleGroup] {
        HealthKitContentRules.groups.filter { !$0.types.contains(type) }
    }

    /// The compilation of the adapter's rules against the generated contracts, with `type`'s contract changed.
    private static func compile(
        _ type: HealthKitSourceType,
        change: (inout ContractDraft) -> Void
    ) throws -> HealthKitContentCompiler.Compilation {
        let row = try #require(HealthKitContract.rows.first { $0.sourceTypeIdentifier == type.rawValue })
        let id = try #require(row.measurementIDs.first)
        var contracts = HealthKitContentCompiler.generatedContracts
        var draft = ContractDraft(try #require(contracts[id]))
        change(&draft)
        contracts[id] = draft.contract
        return HealthKitContentCompiler.compile(contracts: contracts)
    }

    /// Checks that changing `type`'s contract as `change` says refuses the type as not yet convertible for `defect`.
    private static func expectRefused(
        _ type: HealthKitSourceType,
        _ defect: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        change: (inout ContractDraft) -> Void
    ) throws {
        expectRefused(type, defect, in: try compile(type, change: change), sourceLocation: sourceLocation)
    }

    /// Checks that `compilation` refuses `type` with `refusal`, by default as not yet convertible, mints none of its
    /// outputs, and names `defect` as its only defect beyond the adapter's own compilation's.
    private static func expectRefused(
        _ type: HealthKitSourceType,
        _ defect: String,
        in compilation: HealthKitContentCompiler.Compilation,
        as refusal: HealthKitConversionError? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let plan = compilation.byIdentifier[type.rawValue]
        guard case .refused(let refused)? = plan?.route else {
            Issue.record("\(type.rawValue) is not refused", sourceLocation: sourceLocation)
            return
        }
        #expect(refused == refusal ?? .notYetConvertible(type), sourceLocation: sourceLocation)
        #expect(plan?.outputs.isEmpty == true, sourceLocation: sourceLocation)
        #expect(ownDefects(of: compilation) == ["\(type.rawValue): \(defect)"], sourceLocation: sourceLocation)
    }
}


extension ComponentContract {
    /// The component under `id`, read in `quantity`, publishing only the result codes `keep` keeps.
    func with(id: String? = nil, quantity: QuantityContract? = nil, keeping keep: (ResultCodeContract) -> Bool = { _ in true }) -> ComponentContract {
        ComponentContract(
            id: id ?? self.id,
            system: system,
            code: code,
            quantity: quantity ?? self.quantity,
            resultCodeSystem: resultCodeSystem,
            resultCodes: resultCodes.filter(keep)
        )
    }
}

#endif
