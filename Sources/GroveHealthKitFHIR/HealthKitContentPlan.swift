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


/// One output a source type's conversion mints, and how its draft enters the graph.
///
/// Additions draft through the slot and retractions name its output, so both read one table: a conversion can never
/// mint an identity a retraction cannot name.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitOutputSlot: Sendable {
    /// The role, discriminator, resource type and retraction role.
    let output: HealthKitOutput
    /// The envelope statements the output carries.
    let links: ExchangeOutputDraft.Links
    /// Whether the output states the primary under `derivedFrom`.
    let derivedFromPrimary: Bool
    /// The registered format of the native artifact a document carries.
    let artifactFormatCode: String?

    /// The one Observation of a measurement, or an ECG's waveform: a primary output linking everything.
    static func primary(role: String, discriminator: String = "single") -> HealthKitOutputSlot {
        HealthKitOutputSlot(
            output: HealthKitOutput(role: role, discriminator: discriminator, resourceType: .observation, retractionRole: .primaryOutput),
            links: .all,
            derivedFromPrimary: false,
            artifactFormatCode: nil
        )
    }

    /// An Observation derived from the primary, such as an ECG's average heart rate.
    static func derived(role: String, discriminator: String) -> HealthKitOutputSlot {
        HealthKitOutputSlot(
            output: HealthKitOutput(role: role, discriminator: discriminator, resourceType: .observation, retractionRole: .childOutput),
            links: .all,
            derivedFromPrimary: true,
            artifactFormatCode: nil
        )
    }

    /// A document carrying a native artifact: it links its subject, recording device and studies, never a gateway or
    /// manual entry.
    static func document(role: String, format: RegisteredRecordingFormat) -> HealthKitOutputSlot {
        HealthKitOutputSlot(
            output: HealthKitOutput(role: role, discriminator: "single", resourceType: .documentReference, retractionRole: .sourceArtifact),
            links: [.subject, .recordingDevice, .studies],
            derivedFromPrimary: false,
            artifactFormatCode: format.rawValue
        )
    }

    /// The draft of `resource` in this slot.
    func draft(_ resource: ExchangeOutputDraft.Resource) -> ExchangeOutputDraft {
        ExchangeOutputDraft(
            role: output.role,
            discriminator: output.discriminator,
            resource: resource,
            links: links,
            derivedFromPrimary: derivedFromPrimary,
            artifactFormatCode: artifactFormatCode
        )
    }
}


/// Everything known about converting one HealthKit source type before any sample arrives, compiled once per process
/// from the generated contracts and ``HealthKitContentRules``.
///
/// Compiling never traps: a rule its contract cannot satisfy refuses its type as not yet convertible and names the
/// mismatch in ``compileDefects``, which CI keeps to the known set.
@available(iOS 18, macOS 15, watchOS 11, *)
final class HealthKitContentPlan: Sendable {
    /// What a source type converts through. Each payload lives in its own box, so a plan costs only what its route
    /// holds, not the largest route's size.
    indirect enum Route: Sendable {
        /// One Observation, built from the sample.
        case observation(ObservationPlan)
        /// The ECG waveform and its average heart rate, built from the caller's ECG record; a bare sample is refused.
        case electrocardiogram(HealthKitECGContent)
        /// A recording document, built from the caller's record; a bare sample is refused.
        case recording(DocumentPlan)
        /// A clinical record or CDA document, carried from the sample.
        case clinical(DocumentPlan)
        /// Nothing converts: every record of the type is refused with this error.
        case refused(HealthKitConversionError)
    }

    /// Every plan and every defect, compiled on first use.
    private static let compilation = HealthKitContentCompiler.compile()

    /// Every plan, in inventory row order.
    static var all: [HealthKitContentPlan] {
        compilation.plans
    }

    /// One line per rule or contract the compiler could not reconcile, in inventory row order.
    static var compileDefects: [String] {
        compilation.defects
    }

    /// The source type.
    let sourceType: HealthKitSourceType
    /// The type's inventory row, as the public catalog states it.
    let entry: HealthKitCatalogEntry
    /// What the type converts through.
    let route: Route
    /// Every output a conversion of the type mints, primary first; empty for a refused type, except a clinical type on
    /// watchOS, which another platform may have emitted and a retraction must still name.
    let outputs: [HealthKitOutputSlot]
    /// Which metadata keys the conversion consumes.
    let metadata: MetadataRule
    /// The unit a quantity read in its contract's unit is bound to.
    let unitBinding: HealthKitUnitBinding?

    /// The plan of `sourceType`.
    init(
        _ sourceType: HealthKitSourceType,
        entry: HealthKitCatalogEntry,
        route: Route,
        outputs: [HealthKitOutputSlot] = [],
        metadata: MetadataRule = .allowlist,
        unitBinding: HealthKitUnitBinding? = nil
    ) {
        self.sourceType = sourceType
        self.entry = entry
        self.route = route
        self.outputs = outputs
        self.metadata = metadata
        self.unitBinding = unitBinding
    }

    /// The plan of a sample's type, or `nil` for a type the inventory does not list: one hashed lookup.
    static func plan(for sample: HKSample) -> HealthKitContentPlan? {
        compilation.byIdentifier[sample.sampleType.identifier]
    }

    /// The plan of a source type. The generator emits one source type per inventory row and the compiler plans every
    /// row, so every type has one.
    static subscript(type: HealthKitSourceType) -> HealthKitContentPlan {
        guard let plan = compilation.byIdentifier[type.rawValue] else {
            preconditionFailure("The HealthKit inventory row for \(type.rawValue) is generated from the same catalog.")
        }
        return plan
    }
}


extension Coding {
    /// A coding of `code` in `system`, with `display` when one is given.
    init(_ code: String, display: String? = nil, system: FHIRPrimitive<FHIRURI>) {
        self.init(code: code.asFHIRStringPrimitive(), display: display?.asFHIRStringPrimitive(), system: system)
    }

    /// A coding of `code` in the CodeSystem `system` names, with `display` when one is given.
    init(_ code: String, display: String? = nil, system: String) {
        self.init(code, display: display, system: FHIRPrimitive(FHIRURI(stringLiteral: system)))
    }

    /// The coding a contract states.
    init(_ contract: CodingContract) {
        self.init(contract.code, display: contract.display, system: contract.system)
    }
}


extension HealthKitSourceType {
    /// The `healthkit-source-type` extension: the exact SDK type as lineage, never claimed as a clinical or document
    /// type coding.
    var lineage: Extension {
        Extension(url: Canonicals.healthKitSourceTypeExtension, value: .code(rawValue.asFHIRStringPrimitive()))
    }
}

#endif
