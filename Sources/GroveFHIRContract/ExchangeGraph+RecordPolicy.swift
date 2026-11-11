//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

import Foundation
import ModelsR4


extension ExchangeGraph {
    /// One record of an active Bundle as the checks read it.
    struct ActiveRecord {
        /// The position of its conversion Provenance in `Bundle.entry`.
        let index: Int
        let source: RoledIdentifier
        /// The fullUrls of its outputs, in target order.
        let targets: [String]
    }

    private struct ActiveOutput {
        let sourceRecord: RoledIdentifier
        let resourceType: String
    }

    /// A subject one output states: a complete pair, or the Patient entry that names none or several.
    enum SubjectStatement: Hashable {
        case pair(BusinessIdentifier)
        case entry(String)
    }

    /// The retraction-target role that addresses the source record as a whole rather than one emitted node.
    private static let sourceRecordTargetRole = "source-record"

    static func rule(for error: ExchangeIdentityError) -> ExchangeGraphRule {
        switch error {
        case .identifierSystemRoleMismatch:
            .mobileExchangeIdentitySystemRole
        case .invalidIdentifierRole, .duplicateIdentifierRole:
            .mobileExchangeIdentifierRole
        case .invalidIdentifierSystem, .nonCanonicalIdentifierSystem, .missingIdentifierSystem:
            .mobileExchangeOpaqueResourceIdentity
        default:
            .mobileExchangeUnclassified
        }
    }

    static func validateEntryResourcePolicy(
        kind: Kind,
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        let activeTypes = ExchangeContract.activeOutputResourceTypes
            .union(ExchangeContract.activeSupportingResourceTypes)
            .union([ExchangeContract.activeLifecycleResourceType])
        for (index, entry) in entries.enumerated() {
            guard let resource = entry.resource else {
                throw .invalidEntries("Bundle entry has no resource")
            }
            switch kind {
            case .active:
                guard activeTypes.contains(resource.resourceType) else {
                    throw .ruleViolation(.mobileExchangeEntryResourceType)
                }
            case .retraction:
                guard resource.resourceType == ResourceType.provenance.rawValue
                        || resource.resourceType == ResourceType.device.rawValue else {
                    throw .ruleViolation(.mobileRetractionNoClinicalCopy)
                }
            }
            do {
                guard let object = try document.resourceObject(at: index) as? [String: Any]
                else {
                    throw ExchangeGraphError.invalidEntries("Bundle entry resource is not an object")
                }
                guard object["contained"] == nil,
                      try !document.resourceObjects(at: index).contains(where: refersToContainedResource) else {
                    throw ExchangeGraphError.ruleViolation(.mobileExchangeContainedResourceProhibited)
                }
            } catch let error as ExchangeGraphError {
                throw error
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
        }
    }

    /// Where an entry states its key, for a diagnostic.
    static func entryKeyLocation(_ index: Int) -> String {
        "Bundle.entry[\(index)].extension.valueIdentifier"
    }

    static func validateActive(entries: [BundleEntry], document: ValidationDocument) throws(ExchangeGraphError) {
        try validateActiveProfileClaims(entries: entries, document: document)
        let provenances = try validatedActiveProvenances(entries: entries)
        let outputs = try validatedActiveOutputs(entries, document: document)
        try validateSourceMarkers(entries: entries, document: document)
        let records = try validatedActiveRecords(provenances, outputs: outputs)
        try validateRecordingDocuments(entries, records: records, document: document)
        try validateRecordBoundaries(records, entries: entries, document: document)
        try validateSingleSubject(entries: entries)
        try validateStudyContext(entries: entries)
        try validateSupportingConnectivity(kind: .active, entries: entries, document: document)
        try validateAdapterProvenanceGraph(records: records, entries: entries, document: document)
    }

    /// Every Provenance of an active Bundle is one transform assertion with its times and its one assembler.
    private static func validatedActiveProvenances(
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) -> [(index: Int, provenance: Provenance)] {
        let provenances = lifecycleProvenances(in: entries)
        var kinds: [LifecycleKind?] = []
        for (_, provenance) in provenances {
            kinds.append(try lifecycleKind(of: provenance))
        }
        guard !provenances.isEmpty, kinds.allSatisfy({ $0 == .active }) else {
            throw .ruleViolation(.mobileExchangeTransformProvenance)
        }
        try validateRecordTimes(of: provenances)
        let applicationURLs = applicationDeviceURLs(in: entries)
        guard provenances.allSatisfy({ _, provenance in
            exactAssembler(in: provenance).map { assemblerResolves($0, applicationURLs: applicationURLs) } == true
        }) else {
            throw .ruleViolation(.mobileExchangeTransformProvenance)
        }
        return provenances
    }

    /// Every lifecycle Provenance states when its record occurred and when it was recorded.
    private static func validateRecordTimes(
        of provenances: [(index: Int, provenance: Provenance)]
    ) throws(ExchangeGraphError) {
        for (index, provenance) in provenances where !hasRequiredTimes(provenance) {
            throw diagnostic(.mobileExchangeRecordTimes, location: "Bundle.entry[\(index)].resource")
        }
    }

    private static func lifecycleProvenances(in entries: [BundleEntry]) -> [(index: Int, provenance: Provenance)] {
        entries.enumerated().compactMap { index, entry in
            guard case .provenance(let provenance)? = entry.resource else {
                return nil
            }
            return (index, provenance)
        }
    }

    /// Every output's source record and type, by its fullUrl.
    private static func validatedActiveOutputs(
        _ entries: [BundleEntry], document: ValidationDocument
    ) throws(ExchangeGraphError) -> [String: ActiveOutput] {
        var outputs: [String: ActiveOutput] = [:]
        do {
            for (index, entry) in entries.enumerated() {
                if let (fullURL, output) = try validatedActiveOutput(from: entry, at: index, document: document) {
                    outputs[fullURL] = output
                }
            }
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .ruleViolation(.mobileOutputSourceOutputRequired)
        }
        guard !outputs.isEmpty else {
            throw .ruleViolation(.mobileExchangeOutputRequired)
        }
        return outputs
    }

    private static func validatedActiveOutput(
        from entry: BundleEntry, at index: Int, document: ValidationDocument
    ) throws -> (fullURL: String, output: ActiveOutput)? {
        guard let key = document.entryKey(at: index) else {
            throw ExchangeIdentityError.missingIdentifierSystem
        }
        let identifiers = try document.typedResourceIdentifiers(at: index)
        guard Set(identifiers).count == identifiers.count else {
            throw ExchangeIdentityError.duplicateEntryIdentifier(key.identifier)
        }
        if case .device(let device)? = entry.resource {
            try validateDeviceIdentity(device, entryKey: key, identifiers: identifiers)
        }
        guard let resource = entry.resource, isActiveOutput(resource) else {
            return nil
        }
        let sourceOutputs = identifiers.filter { $0.role == .sourceOutput }
        let sourceRecords = identifiers.filter { $0.role == .sourceRecord }
        guard key.role == .sourceOutput,
              sourceOutputs == [key],
              sourceRecords.count == 1,
              let fullURL = entry.fullUrl?.value?.url.absoluteString else {
            throw ExchangeGraphError.ruleViolation(.mobileOutputSourceOutputRequired)
        }
        if case .documentReference(let document) = resource {
            try validateRecordingDocumentTypedIdentity(document, identifiers: identifiers)
        }
        return (fullURL, ActiveOutput(sourceRecord: sourceRecords[0], resourceType: resource.resourceType))
    }

    /// Partitions an active Bundle into records: each Provenance names a source record no other names, and every output
    /// is targeted by exactly one Provenance, the one of the output's own source record.
    private static func validatedActiveRecords(
        _ provenances: [(index: Int, provenance: Provenance)],
        outputs: [String: ActiveOutput]
    ) throws(ExchangeGraphError) -> [ActiveRecord] {
        var sources: Set<RoledIdentifier> = []
        var sourceByIndex: [Int: RoledIdentifier] = [:]
        for (index, provenance) in provenances {
            let source = try exactSourceEntity(in: provenance)
            guard sources.insert(source).inserted else {
                throw diagnostic(.mobileExchangeDistinctSourceRecord, location: "Bundle.entry[\(index)].resource.entity")
            }
            sourceByIndex[index] = source
        }
        var records: [ActiveRecord] = []
        for (index, provenance) in provenances {
            guard let source = sourceByIndex[index] else {
                continue
            }
            let targets = try validatedTargets(of: provenance, at: index, outputs: outputs)
            records.append(ActiveRecord(index: index, source: source, targets: targets))
        }
        var targeted: Set<String> = []
        for target in records.flatMap(\.targets) {
            guard targeted.insert(target).inserted else {
                throw diagnostic(.mobileExchangeOutputTargetedOnce, location: "Bundle.entry")
            }
        }
        guard targeted.count == outputs.count else {
            throw diagnostic(.mobileExchangeOutputTargetedOnce, location: "Bundle.entry")
        }
        for record in records where record.targets.contains(where: { outputs[$0]?.sourceRecord != record.source }) {
            throw diagnostic(.mobileExchangeProvenanceTargets, location: "Provenance.target")
        }
        return records
    }

    private static func validatedTargets(
        of provenance: Provenance,
        at index: Int,
        outputs: [String: ActiveOutput]
    ) throws(ExchangeGraphError) -> [String] {
        guard !provenance.target.isEmpty else {
            throw diagnostic(.mobileExchangeOutputRequired, location: "Bundle.entry[\(index)].resource.target")
        }
        var targets: [String] = []
        var seen: Set<String> = []
        for (targetIndex, target) in provenance.target.enumerated() {
            guard let reference = validActiveTarget(target, outputs: outputs) else {
                throw diagnostic(.mobileExchangeProvenanceTargets, location: "Provenance.target")
            }
            guard seen.insert(reference).inserted else {
                throw diagnostic(.mobileExchangeOutputTargetedOnce, location: "Bundle.entry[\(index)].resource.target[\(targetIndex)]")
            }
            targets.append(reference)
        }
        return targets
    }

    /// A literal reference stays inside its record or reaches a shared node; between records it is identifier-only.
    ///
    /// A lifecycle Provenance is neither an output nor a shared node, so nothing references one: followed, the reference
    /// would pull another record's Provenance and outputs into the referring record.
    private static func validateRecordBoundaries(
        _ records: [ActiveRecord],
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        var recordByOutput: [String: Int] = [:]
        var recordByProvenance: [String: Int] = [:]
        for record in records {
            for target in record.targets {
                recordByOutput[target] = record.index
            }
            if let fullURL = entries[record.index].fullUrl?.value?.url.absoluteString {
                recordByProvenance[fullURL] = record.index
            }
        }
        try validateLiteralReferences(entries: entries, document: document) { referrer, reference in
            let ownRecord = recordByOutput[referrer] ?? recordByProvenance[referrer]
            let reachesProvenance = recordByProvenance[reference] != nil
            let reachesOtherRecord = recordByOutput[reference].map { $0 != ownRecord } ?? false
            return reachesProvenance || reachesOtherRecord
        }
    }

    /// Throws `cross-record-reference` for the first literal reference, in entry order, that `crosses` refuses.
    ///
    /// - parameter crosses: Whether the entry with fullUrl `referrer` may not reference `reference` literally.
    private static func validateLiteralReferences(
        entries: [BundleEntry],
        document: ValidationDocument,
        crosses: (_ referrer: String, _ reference: String) -> Bool
    ) throws(ExchangeGraphError) {
        for (index, entry) in entries.enumerated() {
            let fullURL = entry.fullUrl?.value?.url.absoluteString ?? ""
            let objects: [[String: Any]]
            do {
                objects = try document.resourceObjects(at: index)
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            for reference in objects.compactMap({ $0["reference"] as? String }) where crosses(fullURL, reference) {
                let resource = try? document.resourceObject(at: index)
                let path = resource.flatMap { elementPath(ofReference: reference, in: $0 as Any) } ?? ""
                throw diagnostic(.mobileExchangeCrossRecordReference, location: "Bundle.entry[\(index)].resource.\(path).reference")
            }
        }
    }

    /// The FHIR-style path of the first element stating `reference`, members in name order.
    private static func elementPath(ofReference reference: String, in value: Any, path: String = "") -> String? {
        if let object = value as? [String: Any] {
            if object["reference"] as? String == reference {
                return path
            }
            for key in object.keys.sorted() {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if let child = object[key], let found = elementPath(ofReference: reference, in: child, path: childPath) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                if let found = elementPath(ofReference: reference, in: child, path: "\(path)[\(index)]") {
                    return found
                }
            }
        }
        return nil
    }

    private static func validateSingleSubject(entries: [BundleEntry]) throws(ExchangeGraphError) {
        guard subjectStatements(in: entries).count <= 1 else {
            throw diagnostic(.mobileExchangeSingleSubject, location: "Bundle.entry")
        }
    }

    /// The one subject pair a Bundle's outputs state, or `nil` when they state none, several, or a Patient entry that
    /// names none or several: a retraction states no subject at all.
    static func bundleSubject(in entries: [BundleEntry]) -> BusinessIdentifier? {
        let statements = subjectStatements(in: entries)
        guard statements.count == 1, case .pair(let subject)? = statements.first else {
            return nil
        }
        return subject
    }

    /// The Bundle's Patient entries by fullUrl, which a literal subject resolves against.
    static func patients(in entries: [BundleEntry]) -> [String: Patient] {
        var patients: [String: Patient] = [:]
        for entry in entries {
            if case .patient(let patient)? = entry.resource, let fullURL = entry.fullUrl?.value?.url.absoluteString {
                patients[fullURL] = patient
            }
        }
        return patients
    }

    static func subjectStatements(in entries: [BundleEntry]) -> Set<SubjectStatement> {
        let patients = Self.patients(in: entries)
        return Set(entries.compactMap { entry in
            guard let resource = entry.resource, isActiveOutput(resource), let subject = outputSubject(of: resource) else {
                return nil
            }
            return subjectStatement(subject, patients: patients)
        })
    }

    /// A logical reference states its pseudonym pair, and a literal one the Patient entry's one untyped pair.
    static func subjectStatement(_ reference: Reference, patients: [String: Patient]) -> SubjectStatement? {
        guard let literal = reference.reference?.value?.string else {
            return reference.identifier.flatMap { try? BusinessIdentifier($0) }.map(SubjectStatement.pair)
        }
        guard let patient = patients[literal] else {
            return nil
        }
        let pairs = (patient.identifier ?? []).compactMap { identifier -> BusinessIdentifier? in
            let isTyped = identifier.type?.coding?.contains {
                $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
            } == true
            return isTyped ? nil : try? BusinessIdentifier(identifier)
        }
        return pairs.count == 1 ? .pair(pairs[0]) : .entry(literal)
    }

    private static func validateRecordingDocumentTypedIdentity(
        _ document: DocumentReference,
        identifiers: [RoledIdentifier]
    ) throws(ExchangeGraphError) {
        let writerCount = identifiers.filter { $0.role == .writerRecord }.count
        guard document.content.count == 1,
              identifiers.filter({ $0.role == .sourceRecord }).count == 1,
              identifiers.filter({ $0.role == .sourceOutput }).count == 1,
              identifiers.filter({ $0.role == .sourceArtifact }).count == 1,
              writerCount <= 1,
              identifiers.count == 3 + writerCount else {
            throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
        }
    }

    private static func validateRecordingDocuments(
        _ entries: [BundleEntry], records: [ActiveRecord], document validationDocument: ValidationDocument
    ) throws(ExchangeGraphError) {
        var outputCounts: [String: Int] = [:]
        for record in records {
            for target in record.targets {
                outputCounts[target] = record.targets.count
            }
        }
        for (index, entry) in entries.enumerated() {
            guard case .documentReference(let document)? = entry.resource else {
                continue
            }
            let typed: [RoledIdentifier]
            do {
                typed = try validationDocument.typedResourceIdentifiers(at: index)
            } catch {
                throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
            }
            guard recordingDocumentIdentifiersAreValid(
                document,
                typed: typed,
                sourceDerivedOutputCount: outputCounts[entry.fullUrl?.value?.url.absoluteString ?? ""] ?? 0
            ) else {
                throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
            }
        }
    }

    /// An adapter's source marker belongs on that adapter's outputs alone, once each.
    private static func validateSourceMarkers(entries: [BundleEntry], document: ValidationDocument) throws(ExchangeGraphError) {
        let marker = HealthKitContract.sourceTypeExtension.value?.url.absoluteString
        let adapterRoot = "\(Canonicals.root)/healthkit/"
        for (index, entry) in entries.enumerated() {
            guard let resource = entry.resource, isActiveOutput(resource) else {
                continue
            }
            let extensions: [[String: Any]]
            do {
                let object = try document.resourceObject(at: index) as? [String: Any]
                extensions = object?["extension"] as? [[String: Any]] ?? []
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            let markers = extensions.filter { $0["url"] as? String == marker }.count
            let claimsAdapter = resourceProfiles(resource).contains { $0.hasPrefix(adapterRoot) }
            guard markers == (claimsAdapter ? 1 : 0) else {
                throw diagnostic(.mobileOutputAdapterSourceMarker, location: "\(resource.resourceType).extension")
            }
        }
    }

    /// The output a conversion Provenance target names literally, or `nil` when it names none.
    private static func validActiveTarget(_ target: Reference, outputs: [String: ActiveOutput]) -> String? {
        guard target.identifier == nil,
              let reference = target.reference?.value?.string,
              let output = outputs[reference] else {
            return nil
        }
        if let targetType = target.type?.value?.url.absoluteString, targetType != output.resourceType {
            return nil
        }
        return reference
    }

    private static func recordingDocumentIdentifiersAreValid(
        _ document: DocumentReference,
        typed: [RoledIdentifier],
        sourceDerivedOutputCount: Int
    ) -> Bool {
        let all = document.identifier ?? []
        let roleSystem = Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
        let nonGrove = all.filter { identifier in
            identifier.type?.coding?.contains {
                $0.system?.value?.url.absoluteString == roleSystem
            } != true
        }
        guard all.count == typed.count + nonGrove.count,
              nonGrove.count <= 1 else {
            return false
        }
        guard let governed = nonGrove.first else {
            return true
        }
        return sourceDerivedOutputCount == 1 && isGovernedSourceIdentifier(governed)
    }

    private static func isGovernedSourceIdentifier(_ identifier: Identifier) -> Bool {
        guard (try? BusinessIdentifier(identifier)) != nil,
              identifier.type?.coding?.contains(where: {
                  $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
              }) != true else {
            return false
        }
        guard let type = identifier.type else {
            return true
        }
        let text = type.text?.value?.string
        if text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return false
        }
        let codings = type.coding ?? []
        guard text != nil || !codings.isEmpty else {
            return false
        }
        return codings.allSatisfy { coding in
            guard let rawSystem = coding.system?.value?.url.absoluteString,
                  let system = try? IdentifierSystem(rawSystem),
                  let code = coding.code?.value?.string else {
                return false
            }
            return (try? GovernedSourceIdentifierDisclosurePolicy.IdentifierType(
                system: system,
                code: code,
                display: coding.display?.value?.string
            )) != nil
        }
    }

    static func validateRetraction(entries: [BundleEntry], document: ValidationDocument) throws(ExchangeGraphError) {
        for (index, entry) in entries.enumerated() {
            try validateRetractionEntry(entry, at: index, document: document)
        }
        let provenances = try validatedRetractionProvenances(entries: entries)
        var sources: Set<RoledIdentifier> = []
        for (index, provenance) in provenances {
            let sourceEntity = try exactSourceEntity(in: provenance)
            guard !provenance.target.isEmpty else {
                throw diagnostic(.mobileRetractionTargetRequired, location: "Provenance.target")
            }
            try validateRetractionTargets(provenance.target, sourceEntity: sourceEntity)
            guard sources.insert(sourceEntity).inserted else {
                throw diagnostic(.mobileRetractionProvenance, location: "Bundle.entry[\(index)].resource.entity")
            }
        }
        // literalClosure holds in a retraction Bundle too: nothing references a retraction Provenance.
        let provenanceFullURLs = Set(provenances.compactMap { entries[$0.index].fullUrl?.value?.url.absoluteString })
        try validateLiteralReferences(entries: entries, document: document) { _, reference in
            provenanceFullURLs.contains(reference)
        }
        try validateSupportingConnectivity(kind: .retraction, entries: entries, document: document)
    }

    private static func validateRetractionEntry(
        _ entry: BundleEntry, at index: Int, document: ValidationDocument
    ) throws(ExchangeGraphError) {
        guard let resource = entry.resource else {
            throw .invalidEntries("Bundle entry has no resource")
        }
        switch resource {
        case .provenance(let provenance):
            try validateRetractionProvenanceProfile(provenance)
        case .device(let device):
            let claim = try validateDirectProfileClaim(
                profiles: device.meta?.profile ?? [],
                modes: ProfileClaims.deviceProfileModes,
                rule: .mobileSupportDeviceProfile
            )
            try validateIdentifierRoles(atEntry: index, document: document, claim: claim, rule: .mobileDeviceRecordingDeviceDualIdentity)
            guard let key = document.entryKey(at: index) else {
                throw .ruleViolation(.mobileDeviceRecordingDeviceDualIdentity)
            }
            let identifiers = (try? document.typedResourceIdentifiers(at: index)) ?? []
            try validateDeviceIdentity(device, entryKey: key, identifiers: identifiers)
        default:
            throw .ruleViolation(.mobileRetractionNoClinicalCopy)
        }
    }

    /// Every Provenance of a retraction Bundle is one retraction assertion with its times and its one assembler.
    private static func validatedRetractionProvenances(
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) -> [(index: Int, provenance: Provenance)] {
        let provenances = lifecycleProvenances(in: entries)
        var kinds: [LifecycleKind?] = []
        for (_, provenance) in provenances {
            kinds.append(try lifecycleKind(of: provenance))
        }
        guard !provenances.isEmpty, kinds.allSatisfy({ $0 == .retraction }) else {
            throw .ruleViolation(.mobileRetractionProvenance)
        }
        try validateRecordTimes(of: provenances)
        let applicationURLs = applicationDeviceURLs(in: entries)
        for (_, provenance) in provenances {
            guard provenance.meta?.profile?.contains(Profile.groveMobileRetractionProvenance) == true,
                  let assembler = exactAssembler(in: provenance),
                  assemblerResolves(assembler, applicationURLs: applicationURLs) else {
                throw .ruleViolation(.mobileRetractionNoClinicalCopy)
            }
        }
        return provenances
    }

    private static func validateRetractionTargets(
        _ targets: [Reference],
        sourceEntity: RoledIdentifier
    ) throws(ExchangeGraphError) {
        var logicalTargets: Set<BusinessIdentifier> = []
        for (index, target) in targets.enumerated() {
            let identifier = try validatedRetractionTarget(target, at: index, among: targets.count, sourceEntity: sourceEntity)
            guard logicalTargets.insert(identifier.identifier).inserted else {
                throw diagnostic(.mobileRetractionDistinctTarget, location: "Provenance.target[\(index)].identifier")
            }
        }
    }

    /// The identity of one valid retraction target: a logical Reference with one complete opaque Identifier, exactly one
    /// target role and at most one native record identifier, typed as its role admits or, for a source-record target,
    /// addressing the source record as a whole.
    private static func validatedRetractionTarget(
        _ target: Reference,
        at index: Int,
        among count: Int,
        sourceEntity: RoledIdentifier
    ) throws(ExchangeGraphError) -> RoledIdentifier {
        guard target.reference == nil,
              let identifier = target.identifier,
              let businessIdentifier = try? RoledIdentifier(identifier) else {
            throw .ruleViolation(.mobileRetractionLogicalTarget)
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(businessIdentifier.identifier.value) else {
            throw .ruleViolation(.mobileRetractionOpaqueTarget)
        }
        let roles = target.extension?.filter { $0.url == Canonicals.retractionTargetRole } ?? []
        guard roles.count == 1,
              case .code(let roleCode)? = roles.first?.value,
              let rawRole = roleCode.value?.string else {
            throw .ruleViolation(.mobileRetractionTargetRole)
        }
        let nativeRecordIdentifier = try validatedNativeRecordIdentifier(of: target)
        if rawRole == sourceRecordTargetRole {
            try validateSourceRecordTarget(target, identifier: businessIdentifier, at: index, among: count, sourceEntity: sourceEntity)
            return businessIdentifier
        }
        guard let role = RetractionRecord.Target.Role(rawValue: rawRole) else {
            throw .ruleViolation(.mobileRetractionTargetRole)
        }
        guard let type = target.type?.value?.url.absoluteString,
              let resourceType = ResourceType(rawValue: type) else {
            throw .ruleViolation(.mobileRetractionLogicalTarget)
        }
        do {
            _ = try RetractionRecord.Target(
                identifier: businessIdentifier,
                resourceType: resourceType,
                role: role,
                nativeRecordIdentifier: nativeRecordIdentifier
            )
        } catch {
            throw .ruleViolation(.mobileRetractionRoleTargetType)
        }
        return businessIdentifier
    }

    /// A source-record target names no one resource, so it states no resource type, is the retraction's only target, and
    /// repeats the exact source-record Identifier of the Provenance source entity; each failure names where it occurs.
    private static func validateSourceRecordTarget(
        _ target: Reference,
        identifier: RoledIdentifier,
        at index: Int,
        among count: Int,
        sourceEntity: RoledIdentifier
    ) throws(ExchangeGraphError) {
        guard identifier.role == .sourceRecord else {
            throw diagnostic(.mobileRetractionSourceRecordTarget, location: "Provenance.target[\(index)].identifier")
        }
        guard target.type == nil else {
            throw diagnostic(.mobileRetractionSourceRecordTarget, location: "Provenance.target[\(index)].type")
        }
        guard count == 1 else {
            throw diagnostic(.mobileRetractionSourceRecordTarget, location: "Provenance.target")
        }
        guard identifier == sourceEntity else {
            throw diagnostic(.mobileRetractionSourceRecordTarget, location: "Provenance.target[\(index)].identifier")
        }
    }

    /// The target's one optional native record identifier, which never restates a Grove graph identity.
    private static func validatedNativeRecordIdentifier(of target: Reference) throws(ExchangeGraphError) -> BusinessIdentifier? {
        let natives = target.extension?.filter { $0.url == Canonicals.retractionTargetNativeIdentifier } ?? []
        guard natives.count <= 1 else {
            throw .ruleViolation(.mobileRetractionNativeRecordIdentifier)
        }
        guard let native = natives.first else {
            return nil
        }
        // Any coding in the Grove role system restates a graph identity, whether or not its code parses.
        guard case .identifier(let disclosed)? = native.value,
              !(disclosed.type?.coding ?? []).contains(where: {
                  $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
              }),
              let identifier = try? BusinessIdentifier(disclosed) else {
            throw .ruleViolation(.mobileRetractionNativeRecordIdentifier)
        }
        return identifier
    }
}
