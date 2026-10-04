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
    private static let contracts: [String: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all + [HealthKitContract.bodyMassIndex]).map { ($0.id, $0) }
    ) { first, _ in first }

    /// Every source type's rule.
    private let rules: [HealthKitSourceType: HealthKitContentRules.Rule]
    /// The source types listed under more than one rule.
    private let listedTwice: Set<HealthKitSourceType>
    /// Every defect so far.
    private var defects: [String] = []

    /// A compiler of the hand-written rules.
    private init() {
        let listed = HealthKitContentRules.groups.flatMap { group in
            group.types.map { (type: $0, rule: group.rule) }
        }
        rules = Dictionary(listed.map { ($0.type, $0.rule) }) { first, _ in first }
        let counts = Dictionary(listed.map { ($0.type, 1) }, uniquingKeysWith: +)
        listedTwice = Set(counts.filter { $0.value > 1 }.keys)
    }

    /// Every source type's plan: one per inventory row, in row order, and a refused one for a generated type no row lists.
    static func compile() -> Compilation {
        var compiler = HealthKitContentCompiler()
        var plans: [HealthKitContentPlan] = []
        for row in HealthKitContract.rows {
            guard let type = HealthKitSourceType(rawValue: row.sourceTypeIdentifier) else {
                compiler.defects.append("\(row.sourceTypeIdentifier): no generated source type names the row")
                continue
            }
            plans.append(compiler.plan(row, type: type))
        }
        let planned = Set(plans.map(\.sourceType))
        for type in HealthKitSourceType.allCases where !planned.contains(type) {
            compiler.defects.append("\(type.rawValue): no inventory row lists the type")
            plans.append(HealthKitContentPlan(unlisted: type))
        }
        let byIdentifier = Dictionary(plans.map { ($0.sourceType.rawValue, $0) }) { first, _ in first }
        return Compilation(plans: plans, byIdentifier: byIdentifier, defects: compiler.defects)
    }

    /// The inventory row as the public catalog states it: a multi-measurement row pairs each measurement with its own
    /// profile when the counts match; every other row gives each measurement the row's whole profile list.
    private static func entry(_ row: HealthKitContractRow) -> HealthKitCatalogEntry {
        let measurements = if row.measurementIDs.count > 1, row.measurementIDs.count == row.profiles.count {
            zip(row.measurementIDs, row.profiles).map { HealthKitMeasurementContract(id: $0, profiles: [$1]) }
        } else {
            row.measurementIDs.map { HealthKitMeasurementContract(id: $0, profiles: row.profiles) }
        }
        return HealthKitCatalogEntry(
            sourceTypeIdentifier: row.sourceTypeIdentifier,
            title: row.title,
            measurements: measurements,
            implementationStatus: row.implementationStatus,
            requirement: row.requirement
        )
    }

    /// Why a type without a rule is refused: a correlation member converts only inside its correlation, and any other
    /// type for what its inventory row states.
    private static func refusal(of type: HealthKitSourceType, row: HealthKitContractRow) -> HealthKitConversionError {
        if HealthKitContentRules.bloodPressureMembers.contains(where: { $0.value == type }) {
            return .componentRequiresCorrelation(type)
        }
        return switch row.implementationStatus {
        case .intentionallyUnsupported: .intentionallyUnsupported(type, reason: row.requirement ?? "")
        case .platformExclusive: .platformExclusiveSourceType(type)
        case .supported: .unsupportedSourceType(type)
        }
    }

    /// The contract of a row: its first measurement's.
    private static func contract(of row: HealthKitContractRow) throws(HealthKitContentDefect) -> MeasurementContract {
        guard let id = row.measurementIDs.first, let contract = contracts[id] else {
            throw HealthKitContentDefect("names no generated measurement contract")
        }
        return contract
    }

    /// The direct profiles of a measurement's Observation: a single-profile measurement claims its own, every other
    /// one its shared profile plus HealthKit's.
    private static func profiles(of contract: MeasurementContract) -> [FHIRPrimitive<Canonical>] {
        if ProfileClaims.singleObservationProfiles.contains(contract.profile) {
            return [contract.profile]
        }
        return ProfileClaims.observation(sharedMeasurement: contract.profile, adapter: Profile.healthkitObservation)
    }

    /// How a measurement's effective time is drawn from the sample. A dateTime-or-Period measurement (heart rate)
    /// states its instant: a scalar HealthKit sample stays point-in-time.
    private static func effective(of contract: MeasurementContract) -> EffectiveRule {
        switch contract.effective {
        case .dateTime, .dateTimeOrPeriod: .instant
        case .period: .interval(nonZero: HealthKitContentRules.nonZeroPeriods.contains(contract.id))
        }
    }

    /// The documents of a recording format claim the shared recording-document profile and the row's own.
    private static func recordingProfiles(of row: HealthKitContractRow) -> [FHIRPrimitive<Canonical>] {
        [Profile.groveSensorRecordingDocument] + row.profiles
    }

    /// A clinical type's plan. watchOS has no clinical records, so it refuses the type there, yet keeps its output:
    /// a record another platform emitted can still be retracted.
    private static func clinical(_ document: DocumentPlan, type: HealthKitSourceType, entry: HealthKitCatalogEntry) -> HealthKitContentPlan {
        #if os(watchOS)
        let route = HealthKitContentPlan.Route.refused(.platformExclusiveSourceType(type))
        #else
        let route = HealthKitContentPlan.Route.clinical(document)
        #endif
        let outputs = [HealthKitOutputSlot.document(role: HealthKitContentRules.clinicalRecordRole, format: document.format)]
        return HealthKitContentPlan(type, entry: entry, route: route, outputs: outputs)
    }

    /// The plan of one inventory row.
    private mutating func plan(_ row: HealthKitContractRow, type: HealthKitSourceType) -> HealthKitContentPlan {
        let entry = Self.entry(row)
        guard let rule = rules[type] else {
            if row.implementationStatus == .supported, !HealthKitContentRules.notYetConvertible.contains(type) {
                defects.append("\(type.rawValue): supported, but has no rule and is not declared not yet convertible")
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
        entry: HealthKitCatalogEntry
    ) throws(HealthKitContentDefect) -> HealthKitContentPlan {
        switch rule {
        case .observation(let rule):
            let contract = try Self.contract(of: row)
            let (observation, unitBinding) = try self.observation(rule, contract: contract, type: type)
            let outputs = [HealthKitOutputSlot.primary(role: contract.id)]
            return HealthKitContentPlan(type, entry: entry, route: .observation(observation), outputs: outputs, unitBinding: unitBinding)
        case .electrocardiogram:
            let claim = HealthKitElectrocardiogramClaim.self
            let outputs = [
                HealthKitOutputSlot.primary(role: claim.waveform.role, discriminator: claim.waveform.discriminator),
                HealthKitOutputSlot.derived(role: claim.averageHeartRate.role, discriminator: claim.averageHeartRate.discriminator)
            ]
            return HealthKitContentPlan(type, entry: entry, route: .electrocardiogram(try HealthKitECGContent(sourceType: type)), outputs: outputs)
        case let .recording(format, title):
            let document = DocumentPlan(sourceType: type, format: format, profiles: Self.recordingProfiles(of: row), title: title)
            let outputs = [HealthKitOutputSlot.document(role: HealthKitContentRules.nativeRecordingRole, format: format)]
            return HealthKitContentPlan(type, entry: entry, route: .recording(document), outputs: outputs)
        case .clinicalDocument(let title):
            let document = DocumentPlan(sourceType: type, format: .clinicalDocument, profiles: Self.recordingProfiles(of: row), title: title)
            return Self.clinical(document, type: type, entry: entry)
        case .clinicalRecord(let typeCode):
            let typeCoding = Coding(code: typeCode.asFHIRStringPrimitive(), system: HealthKitContentRules.clinicalRecordTypeSystem)
            let document = DocumentPlan(sourceType: type, format: .fhirResource, profiles: row.profiles, typeCoding: typeCoding, title: row.title)
            return Self.clinical(document, type: type, entry: entry)
        }
    }

    /// The Observation plan of a measurement, and the unit binding of a quantity read in the contract's unit.
    private mutating func observation(
        _ rule: HealthKitContentRules.ObservationRule,
        contract: MeasurementContract,
        type: HealthKitSourceType
    ) throws(HealthKitContentDefect) -> (ObservationPlan, HealthKitUnitBinding?) {
        guard let display = contract.code.display ?? HealthKitContentRules.displays[contract.id] else {
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
        let (value, unitBinding) = try self.value(rule, contract: contract, type: type)
        let plan = ObservationPlan(
            skeleton: skeleton,
            effective: Self.effective(of: contract),
            value: value,
            metadataComponent: try HealthKitContentRules.metadataComponent(of: type, contract: contract)
        )
        return (plan, unitBinding)
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

    /// A quantity read from `source`, and the unit binding of one read in the contract's unit.
    private static func quantity(
        _ source: HealthKitContentRules.QuantitySource,
        contract: MeasurementContract
    ) throws(HealthKitContentDefect) -> (ValueRule, HealthKitUnitBinding?) {
        let quantity = try quantity(of: contract)
        let template = QuantityTemplate(quantity)
        switch source {
        case .contractUnit:
            guard let unit = HealthKitContentRules.ucumUnits[quantity.code] else {
                throw HealthKitContentDefect("reads its quantity in \(quantity.code), which has no HealthKit unit")
            }
            return (.quantity(template, .unit(unit)), HealthKitUnitBinding(ucumCode: quantity.code, displayUnit: quantity.unit, unit: unit))
        case .percent:
            return (.quantity(template, .percent), nil)
        case .platformRate:
            return (.quantity(template, .unit(.count())), nil)
        case .score:
            return (.quantity(template, .score), nil)
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
        func value(_ code: String) throws(HealthKitContentDefect) -> CodeableConcept {
            guard let result = contract.resultCodes.first(where: { $0.code == code }) else {
                throw HealthKitContentDefect("admits no result code \(code)")
            }
            return CodeableConcept(coding: [Coding(result.code, display: result.display, system: system)])
        }
        return .protection(unknown: try value("unknown"), protected: try value("protected"), unprotected: try value("unprotected"))
    }

    /// The panel's members, in the contract's component order, each read in the HealthKit unit of its UCUM code.
    private static func bloodPressureMembers(_ contract: MeasurementContract) throws(HealthKitContentDefect) -> [BloodPressureMember] {
        var members: [BloodPressureMember] = []
        for component in contract.components {
            guard let member = HealthKitContentRules.bloodPressureMembers.first(where: { $0.key == component.id })?.value else {
                throw HealthKitContentDefect("states component \(component.id), which no correlation member states")
            }
            guard let quantity = component.quantity,
                  let template = ComponentTemplate(component),
                  let unit = HealthKitContentRules.ucumUnits[quantity.code] else {
                throw HealthKitContentDefect("reads component \(component.id) in no HealthKit unit")
            }
            members.append(BloodPressureMember(quantityType: HKQuantityTypeIdentifier(rawValue: member.rawValue), unit: unit, template: template))
        }
        guard !members.isEmpty else {
            throw HealthKitContentDefect("states no components")
        }
        return members
    }

    /// How an Observation's value is read, compiled against its contract, and the unit binding of a quantity read in
    /// the contract's unit.
    private mutating func value(
        _ rule: HealthKitContentRules.ObservationRule,
        contract: MeasurementContract,
        type: HealthKitSourceType
    ) throws(HealthKitContentDefect) -> (ValueRule, HealthKitUnitBinding?) {
        switch rule {
        case .quantity(let source):
            return try Self.quantity(source, contract: contract)
        case .coded(let table):
            return (try coded(table, contract: contract, type: type), nil)
        case .occurrence:
            return (try Self.occurrence(contract), nil)
        case .duration:
            let quantity = try Self.quantity(of: contract)
            guard let secondsPerUnit = HealthKitContentRules.durationUnits[quantity.code] else {
                throw HealthKitContentDefect("states its duration in \(quantity.code), neither seconds nor minutes")
            }
            return (.duration(QuantityTemplate(quantity), secondsPerUnit: secondsPerUnit), nil)
        case .protection:
            return (try Self.protection(contract), nil)
        case .bloodPressure:
            return (.bloodPressure(try Self.bloodPressureMembers(contract)), nil)
        case .workout:
            return (.workout(try HealthKitWorkoutContent(contract)), nil)
        case .stateOfMind:
            return (.stateOfMind(try HealthKitStateOfMindContent(contract)), nil)
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
            guard let display = row.sharedDisplay ?? published[row.shared], admitted.contains(row.shared) else {
                unresolved.insert(raw)
                defects.append("\(type.rawValue): value \(raw) reports as \(row.shared), which the contract does not admit")
                continue
            }
            var codings = [Coding(row.shared, display: display, system: system)]
            if let sourceSystem = table.sourceSystem, let source = row.source {
                codings.append(Coding(
                    code: source.asFHIRStringPrimitive(),
                    display: row.sourceDisplay?.asFHIRStringPrimitive(),
                    system: sourceSystem
                ))
            }
            values[raw] = CodeableConcept(coding: codings)
        }
        return .coded(values: values, unresolved: unresolved)
    }
}

#endif
