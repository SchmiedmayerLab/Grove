//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit
import ModelsR4


/// Why a source type's rule does not compile against the generated contracts; the type is refused, never trapped on.
struct HealthKitContentDefect: Error {
    /// What does not fit, worded to follow the source type's identifier.
    let reason: String

    /// The defect `reason`.
    init(_ reason: String) {
        self.reason = reason
    }
}


/// Compiles every source type's content plan, once per process, and records what it cannot reconcile.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitContentCompiler {
    /// The compiled plans and defects.
    struct Compilation: Sendable {
        /// Every plan, in inventory row order.
        let plans: [HealthKitContentPlan]
        /// Every plan, by source-type identifier.
        let byIdentifier: [String: HealthKitContentPlan]
        /// Every defect, in inventory row order.
        let defects: [String]
    }

    /// Every generated measurement contract by id, the first catalog winning, and body-mass index, which no catalog
    /// lists: a row's contract is its first measurement's.
    static let generatedContracts: [String: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all + [HealthKitContract.bodyMassIndex]).map { ($0.id, $0) }
    ) { first, _ in first }

    /// The profiles of a recording or clinical-record document: a row claiming one converts through a document rule.
    private static let documentProfiles: Set<FHIRPrimitive<Canonical>> = [
        Profile.healthkitRecordingDocument,
        Profile.healthkitClinicalRecordDocument
    ]

    /// The contracts rows are compiled against, by measurement id.
    private let contracts: [String: MeasurementContract]
    /// Every listed source type's rule.
    private let rules: [HealthKitSourceType: HealthKitContentRules.Rule]
    /// The source types listed under more than one rule.
    private let listedTwice: Set<HealthKitSourceType>
    /// Every defect so far.
    private var defects: [String] = []

    /// A compiler of `groups` against `contracts`.
    private init(groups: [HealthKitContentRules.RuleGroup], contracts: [String: MeasurementContract]) {
        let listed = groups.flatMap { group in
            group.types.map { (type: $0, rule: group.rule) }
        }
        rules = Dictionary(listed.map { ($0.type, $0.rule) }) { first, _ in first }
        let counts = Dictionary(listed.map { ($0.type, 1) }, uniquingKeysWith: +)
        listedTwice = Set(counts.filter { $0.value > 1 }.keys)
        self.contracts = contracts
    }

    /// Every inventory row's plan, in row order, compiled from `groups` against `contracts`: by default the adapter's
    /// own rules and the generated contracts, which a test replaces to reach each defect.
    static func compile(
        groups: [HealthKitContentRules.RuleGroup] = HealthKitContentRules.groups,
        contracts: [String: MeasurementContract] = generatedContracts
    ) -> Compilation {
        var compiler = HealthKitContentCompiler(groups: groups, contracts: contracts)
        // The generator emits the source types from the inventory rows, one per row.
        let plans = HealthKitContract.rows.compactMap { row in
            HealthKitSourceType(rawValue: row.sourceTypeIdentifier).map { compiler.plan(row, type: $0) }
        }
        let byIdentifier = Dictionary(plans.map { ($0.sourceType.rawValue, $0) }) { first, _ in first }
        return Compilation(plans: plans, byIdentifier: byIdentifier, defects: compiler.defects)
    }

    /// The inventory row as the public catalog states it: a multi-measurement row pairs each measurement with its own
    /// profile when the counts match; every other row gives each measurement the row's whole profile list.
    private static func entry(_ row: HealthKitContractRow) -> HealthKitCatalog.Entry {
        let measurements = if row.measurementIDs.count > 1, row.measurementIDs.count == row.profiles.count {
            zip(row.measurementIDs, row.profiles).map { HealthKitCatalog.Entry.Measurement(id: $0, profiles: [$1]) }
        } else {
            row.measurementIDs.map { HealthKitCatalog.Entry.Measurement(id: $0, profiles: row.profiles) }
        }
        return HealthKitCatalog.Entry(
            sourceTypeIdentifier: row.sourceTypeIdentifier,
            title: row.title,
            measurements: measurements,
            implementationStatus: row.implementationStatus,
            requirement: row.requirement
        )
    }

    /// Why a type without a rule is refused: a correlation member converts only inside its correlation, and any other
    /// type for what its inventory row states. A row admitted only as a recording document is platform exclusive; any
    /// other row the inventory admits is not yet convertible, as this producer version emits no graph for it.
    private static func refusal(of type: HealthKitSourceType, row: HealthKitContractRow) -> HealthKitConversionError {
        if HealthKitContentRules.bloodPressureMembers.contains(where: { $0.value == type }) {
            return .componentRequiresCorrelation(type)
        }
        return switch row.implementationStatus {
        case .intentionallyUnsupported: .intentionallyUnsupported(type, reason: row.requirement ?? "")
        case .platformExclusive where !documentProfiles.isDisjoint(with: row.profiles): .platformExclusiveSourceType(type)
        case .platformExclusive, .supported: .notYetConvertible(type)
        }
    }

    /// Why a row without a rule is a defect, or `nil` when the inventory refuses it by design: a supported row converts
    /// unless declared not yet convertible, and a row claiming a document profile converts to that document.
    private static func missingRule(_ row: HealthKitContractRow, type: HealthKitSourceType) -> String? {
        if row.implementationStatus == .supported, !HealthKitContentRules.notYetConvertible.contains(type) {
            return "supported, but has no rule and is not declared not yet convertible"
        }
        if !documentProfiles.isDisjoint(with: row.profiles) {
            return "claims a document profile, but has no rule"
        }
        return nil
    }

    /// The direct profiles of a measurement's Observation: a single-profile measurement claims its own, every other
    /// one its shared profile plus HealthKit's.
    private static func profiles(of contract: MeasurementContract) -> [FHIRPrimitive<Canonical>] {
        if ProfileClaims.singleObservationProfiles.contains(contract.profile) {
            return [contract.profile]
        }
        return ProfileClaims.observation(sharedMeasurement: contract.profile, adapter: Profile.healthkitObservation)
    }

    /// The documents of a recording format claim the shared recording-document profile and the row's own.
    private static func recordingProfiles(of row: HealthKitContractRow) -> [FHIRPrimitive<Canonical>] {
        [Profile.groveSensorRecordingDocument] + row.profiles
    }

    /// A clinical type's plan. watchOS has no clinical records, so it refuses the type there, yet keeps its output:
    /// a record another platform emitted can still be retracted.
    private static func clinical(_ document: DocumentPlan, type: HealthKitSourceType, entry: HealthKitCatalog.Entry) -> HealthKitContentPlan {
        #if os(watchOS)
        let route = HealthKitContentPlan.Route.refused(.platformExclusiveSourceType(type))
        #else
        let route = HealthKitContentPlan.Route.clinical(document)
        #endif
        let outputs = [HealthKitOutputSlot.document(role: HealthKitContentRules.clinicalRecordRole, format: document.format)]
        return HealthKitContentPlan(type, entry: entry, route: route, outputs: outputs)
    }

    /// The contract of a row: its first measurement's.
    private func contract(of row: HealthKitContractRow) throws(HealthKitContentDefect) -> MeasurementContract {
        guard let id = row.measurementIDs.first, let contract = contracts[id] else {
            throw HealthKitContentDefect("names no generated measurement contract")
        }
        return contract
    }

    /// The plan of one inventory row: under its listed rule, else under the rule its row implies, else refused.
    private mutating func plan(_ row: HealthKitContractRow, type: HealthKitSourceType) -> HealthKitContentPlan {
        let entry = Self.entry(row)
        guard let rule = rules[type] ?? HealthKitContentRules.impliedRule(of: type, status: row.implementationStatus) else {
            if let missing = Self.missingRule(row, type: type) {
                defects.append("\(type.rawValue): \(missing)")
            }
            return HealthKitContentPlan(type, entry: entry, route: .refused(Self.refusal(of: type, row: row)))
        }
        do throws(HealthKitContentDefect) {
            guard !listedTwice.contains(type) else {
                throw HealthKitContentDefect("is listed under more than one rule")
            }
            return try plan(rule, row: row, type: type, entry: entry)
        } catch {
            defects.append("\(type.rawValue): \(error.reason)")
            return HealthKitContentPlan(type, entry: entry, route: .refused(.notYetConvertible(type)))
        }
    }

    /// The plan of a row under its rule.
    private mutating func plan(
        _ rule: HealthKitContentRules.Rule,
        row: HealthKitContractRow,
        type: HealthKitSourceType,
        entry: HealthKitCatalog.Entry
    ) throws(HealthKitContentDefect) -> HealthKitContentPlan {
        switch rule {
        case .observation(let rule):
            let contract = try contract(of: row)
            let observation = try self.observation(rule, contract: contract, type: type)
            let outputs = [HealthKitOutputSlot.primary(role: contract.id)]
            let metadata: MetadataRule = if case .bloodPressure = rule { .bloodPressure } else { .allowlist }
            return HealthKitContentPlan(type, entry: entry, route: .observation(observation), outputs: outputs, metadata: metadata)
        case .electrocardiogram:
            let content = try HealthKitECGContent(sourceType: type)
            let outputs = [content.waveformSlot, content.averageHeartRateSlot]
            return HealthKitContentPlan(type, entry: entry, route: .electrocardiogram(content), outputs: outputs)
        case let .recording(format, title):
            let document = DocumentPlan(sourceType: type, format: format, profiles: Self.recordingProfiles(of: row), title: title)
            let outputs = [HealthKitOutputSlot.document(role: HealthKitContentRules.nativeRecordingRole, format: format)]
            return HealthKitContentPlan(type, entry: entry, route: .recording(document), outputs: outputs)
        case .clinicalDocument(let title):
            let document = DocumentPlan(sourceType: type, format: .clinicalDocument, profiles: Self.recordingProfiles(of: row), title: title)
            return Self.clinical(document, type: type, entry: entry)
        case .clinicalRecord(let typeCode):
            let typeCoding = Coding(typeCode, system: HealthKitContentRules.clinicalRecordTypeSystem)
            let document = DocumentPlan(sourceType: type, format: .fhirResource, profiles: row.profiles, typeCoding: typeCoding, title: row.title)
            return Self.clinical(document, type: type, entry: entry)
        }
    }

    /// The Observation plan of a measurement.
    private mutating func observation(
        _ rule: HealthKitContentRules.ObservationRule,
        contract: MeasurementContract,
        type: HealthKitSourceType
    ) throws(HealthKitContentDefect) -> ObservationPlan {
        guard let display = contract.code.display ?? HealthKitTerminology.displays[contract.code] else {
            throw HealthKitContentDefect("states no display for code \(contract.code.code)")
        }
        let primary = Coding(contract.code.code, display: display, system: contract.code.system)
        let skeleton = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [primary] + contract.requiredCodings.map { Coding($0) }),
            sourceType: type,
            profiles: Self.profiles(of: contract),
            category: HealthKitContentRules.category(of: contract),
            method: contract.method
        )
        return ObservationPlan(
            skeleton: skeleton,
            effective: EffectiveRule(contract),
            value: try value(rule, contract: contract, type: type),
            metadataComponent: try HealthKitContentRules.metadataComponent(of: type, contract: contract)
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitContentCompiler {
    /// The contract's quantity.
    private static func quantity(of contract: MeasurementContract) throws(HealthKitContentDefect) -> QuantityContract {
        guard let quantity = contract.quantity else {
            throw HealthKitContentDefect("states no quantity")
        }
        return quantity
    }

    /// The CodeSystem of the contract's coded results.
    private static func resultCodeSystem(of contract: MeasurementContract) throws(HealthKitContentDefect) -> String {
        guard let system = contract.resultCodeSystem else {
            throw HealthKitContentDefect("states no result CodeSystem")
        }
        return system
    }

    /// A quantity read from `source`. HealthKit keeps a percentage as a fraction, so a contract stated in percent reads
    /// the fraction and states it in percent.
    private static func quantity(
        _ source: HealthKitContentRules.QuantitySource,
        contract: MeasurementContract
    ) throws(HealthKitContentDefect) -> ValueRule {
        let quantity = try quantity(of: contract)
        let template = QuantityTemplate(quantity)
        return switch source {
        case .contract where quantity.code == "%": .quantity(template, .percent)
        case .contract: .quantity(template, .unit(try quantity.binding()))
        case .platformRate: .quantity(template, .platformRate)
        case .score: .quantity(template, .score)
        }
    }

    /// An occurrence: `HKCategoryValue.notApplicable`, reported as the contract's one result code.
    private static func occurrence(_ contract: MeasurementContract) throws(HealthKitContentDefect) -> ValueRule {
        let system = try resultCodeSystem(of: contract)
        guard let occurred = contract.resultCodes.first else {
            throw HealthKitContentDefect("states no result code for the occurrence")
        }
        let value = CodeableConcept(coding: [Coding(occurred.code, display: occurred.display, system: system)])
        return .coded(values: [HKCategoryValue.notApplicable.rawValue: value], unresolved: [])
    }

    /// Whether protection was used, as the contract's unknown, protected and unprotected result codes.
    private static func protection(_ contract: MeasurementContract) throws(HealthKitContentDefect) -> ValueRule {
        let system = try resultCodeSystem(of: contract)
        let results = contract.resultCodes
        return .protection(
            unknown: try results.concept("unknown", system: system),
            protected: try results.concept("protected", system: system),
            unprotected: try results.concept("unprotected", system: system)
        )
    }

    /// The panel's members, in the contract's component order, each read in the HealthKit unit of its UCUM code.
    private static func bloodPressureMembers(_ contract: MeasurementContract) throws(HealthKitContentDefect) -> [BloodPressureMember] {
        guard !contract.components.isEmpty else {
            throw HealthKitContentDefect("states no components")
        }
        return try contract.components.map { component throws(HealthKitContentDefect) in
            guard let member = HealthKitContentRules.bloodPressureMembers.first(where: { $0.key == component.id })?.value else {
                throw HealthKitContentDefect("states component \(component.id), which no correlation member states")
            }
            let (template, quantity) = try contract.quantityComponent(component.id)
            let quantityType = HKQuantityTypeIdentifier(rawValue: member.rawValue)
            return BloodPressureMember(component: component.id, quantityType: quantityType, binding: try quantity.binding(), template: template)
        }
    }

    /// How an Observation's value is read, compiled against its contract.
    private mutating func value(
        _ rule: HealthKitContentRules.ObservationRule,
        contract: MeasurementContract,
        type: HealthKitSourceType
    ) throws(HealthKitContentDefect) -> ValueRule {
        switch rule {
        case .quantity(let source):
            return try Self.quantity(source, contract: contract)
        case .coded(let table):
            return try coded(table, contract: contract, type: type)
        case .occurrence:
            return try Self.occurrence(contract)
        case .duration:
            let quantity = try Self.quantity(of: contract)
            guard let secondsPerUnit = HealthKitContentRules.durationUnits[quantity.code] else {
                throw HealthKitContentDefect("states its duration in \(quantity.code), neither seconds nor minutes")
            }
            return .duration(QuantityTemplate(quantity), secondsPerUnit: secondsPerUnit)
        case .protection:
            return try Self.protection(contract)
        case .bloodPressure:
            return .bloodPressure(try Self.bloodPressureMembers(contract))
        case .workout:
            return .workout(try HealthKitWorkoutContent(contract))
        case .stateOfMind:
            return .stateOfMind(try HealthKitStateOfMindContent(contract))
        }
    }

    /// A category value's codings: the shared one, then the source case's. A value whose shared code the contract
    /// does not admit has no normative code: it stays unresolved and is a defect, while the type's other values convert.
    private mutating func coded(
        _ table: CodedTable,
        contract: MeasurementContract,
        type: HealthKitSourceType
    ) throws(HealthKitContentDefect) -> ValueRule {
        let system = try Self.resultCodeSystem(of: contract)
        let published = Dictionary(contract.resultCodes.map { ($0.code, $0.display) }) { first, _ in first }
        let admitted = Set(contract.allowedValues).union(published.keys)
        var values: [Int: CodeableConcept] = [:]
        var unresolved: Set<Int> = []
        for (raw, row) in table.rows {
            guard values[raw] == nil, !unresolved.contains(raw) else {
                throw HealthKitContentDefect("maps value \(raw) twice")
            }
            guard let display = row.display ?? published[row.shared], admitted.contains(row.shared) else {
                unresolved.insert(raw)
                defects.append("\(type.rawValue): value \(raw) reports as \(row.shared), which the contract does not admit")
                continue
            }
            var codings = [Coding(row.shared, display: display, system: system)]
            if let sourceSystem = table.sourceSystem, let source = row.source {
                codings.append(Coding(source, display: row.sourceDisplay, system: sourceSystem))
            }
            values[raw] = CodeableConcept(coding: codings)
        }
        return .coded(values: values, unresolved: unresolved)
    }
}

#endif
