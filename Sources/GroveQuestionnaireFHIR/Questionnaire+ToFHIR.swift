//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract
public import GroveQuestionnaire
public import ModelsR4


/// An error occurring while exporting a natively declared questionnaire to FHIR.
public struct ExportError: LocalizedError {
    public let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}


/// What the export needs to know about the questionnaire beyond the item being written.
@available(iOS 18, macOS 15, watchOS 11, *)
struct FHIRExportContext {
    /// Every task in the questionnaire, follow-ups included, keyed by its id.
    private let tasksById: [GroveQuestionnaire.Questionnaire.Task.ID: GroveQuestionnaire.Questionnaire.Task]

    init(_ questionnaire: GroveQuestionnaire.Questionnaire) {
        var tasksById: [GroveQuestionnaire.Questionnaire.Task.ID: GroveQuestionnaire.Questionnaire.Task] = [:]
        func collect(_ tasks: [GroveQuestionnaire.Questionnaire.Task]) {
            for task in tasks {
                tasksById[task.id] = task
                collect(task.kind.followUpTasks)
            }
        }
        collect(questionnaire.sections.flatMap(\.tasks))
        self.tasksById = tasksById
    }

    /// A `Quantity` expressed in the unit the given question is answered in.
    ///
    /// qty-3 makes a coded `Quantity` without a system an error, so a unit whose system the
    /// question does not declare is carried as display text rather than as a code.
    func quantity(_ value: Double, unitCode: String?, forTaskWithId taskId: GroveQuestionnaire.Questionnaire.Task.ID) -> Quantity {
        let system = unitCode.flatMap { unitSystem(ofUnit: $0, forTaskWithId: taskId) }
        return Quantity(
            code: system == nil ? nil : unitCode?.asFHIRStringPrimitive(),
            system: system?.asFHIRURIPrimitive(),
            unit: unitCode?.asFHIRStringPrimitive(),
            value: value.asFHIRDecimalPrimitive()
        )
    }

    private func unitSystem(ofUnit code: String, forTaskWithId taskId: GroveQuestionnaire.Questionnaire.Task.ID) -> URL? {
        guard case .numeric(let config)? = tasksById[taskId]?.kind.variant else {
            return nil
        }
        return config.unitOptions.first { $0.code == code }?.system ?? config.unitSystem
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire {
    /// Authoring-time diagnostics for a FHIR questionnaire: everything that would keep
    /// this renderer from administering it faithfully, as human-readable findings.
    ///
    /// Run this in study tooling and tests so unsupported features surface at build
    /// time instead of in front of participants. An empty result means the
    /// questionnaire converts cleanly and carries no administration warnings.
    public static func authoringDiagnostics(
        for questionnaire: ModelsR4.Questionnaire,
        evaluationInstant: Date,
        using options: ConversionOptions = .init()
    ) -> [String] {
        do {
            let converted = try GroveQuestionnaire.Questionnaire(
                questionnaire,
                evaluationInstant: evaluationInstant,
                using: options
            )
            return converted.metadata.administrationWarnings
        } catch {
            return [error.localizedDescription]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.Questionnaire {
    /// Exports a natively declared Grove questionnaire as a FHIR R4 `Questionnaire`.
    ///
    /// Together with `ModelsR4.QuestionnaireResponse.init(_:)` this closes the round
    /// trip: instruments authored with the Swift DSL serve FHIR-native consumers.
    public init(
        _ questionnaire: GroveQuestionnaire.Questionnaire,
        repositoryID: RepositoryID? = nil
    ) throws {
        guard let url = questionnaire.metadata.url else {
            throw ContractError.missingQuestionnaireURL
        }
        guard let version = questionnaire.metadata.version else {
            throw ContractError.missingQuestionnaireVersion
        }
        guard ContractRules.isSemanticVersion(version) else {
            throw ContractError.invalidQuestionnaireVersion(version)
        }
        let canonical = "\(url.absoluteString)|\(version)"
        guard !url.absoluteString.contains("|"),
              !url.absoluteString.contains("#"),
              !version.contains("|"),
              !version.contains("#") else {
            throw ContractError.invalidQuestionnaireCanonical(canonical)
        }
        self.init(status: FHIRPrimitive(Self.publicationStatus(of: questionnaire.metadata.lifecycle)))
        self.id = repositoryID?.primitive
        self.meta = Meta(profile: [Profile.groveQuestionnaire])
        applyMetadata(questionnaire.metadata)
        let items = try Self.items(of: questionnaire)
        guard !items.isEmpty else {
            throw ContractError.emptyQuestionnaire
        }
        self.item = items
    }

    private static func publicationStatus(
        of lifecycle: GroveQuestionnaire.Questionnaire.PublicationLifecycle
    ) -> PublicationStatus {
        switch lifecycle {
        case .draft: .draft
        case .active: .active
        case .retired: .retired
        case .unknown: .unknown
        }
    }

    /// The top-level items, each authored section wrapped in the group it was read from.
    private static func items(of questionnaire: GroveQuestionnaire.Questionnaire) throws -> [QuestionnaireItem] {
        let context = FHIRExportContext(questionnaire)
        var items: [QuestionnaireItem] = []
        for section in questionnaire.sections {
            let sectionItems = try QuestionnaireItem.items(for: section, using: context)
            guard !sectionItems.isEmpty else {
                continue
            }
            guard let groupId = section.fhirGroupId else {
                // A section synthesized around ungrouped top-level items is not a FHIR group;
                // re-emitting it would publish a linkId nobody authored.
                items.append(contentsOf: sectionItems)
                continue
            }
            var group = QuestionnaireItem(
                linkId: groupId.asFHIRStringPrimitive(),
                type: FHIRPrimitive(QuestionnaireItemType.group)
            )
            if !section.title.isEmpty {
                group.text = section.title.asFHIRStringPrimitive()
            }
            if let shortTitle = section.shortTitle {
                group.extension = [.shortText(shortTitle)]
            }
            group.item = sectionItems
            items.append(group)
        }
        return items
    }

    private mutating func applyMetadata(_ metadata: GroveQuestionnaire.Questionnaire.Metadata) {
        var resourceExtensions = [
            Extension(
                url: Canonicals.versionAlgorithm,
                value: .coding(Coding(
                    code: "semver".asFHIRStringPrimitive(),
                    system: Canonicals.versionAlgorithmCodeSystem
                ))
            )
        ]
        resourceExtensions.append(contentsOf: metadata.variables.map { variable in
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/variable",
                value: .expression(Expression(
                    expression: variable.expression.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath")),
                    name: variable.name.asFHIRStringPrimitive()
                ))
            )
        })
        if metadata.entryMode != .random {
            resourceExtensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-entryMode",
                value: .code(FHIRPrimitive(ModelsR4.FHIRString(metadata.entryMode.rawValue)))
            ))
        }
        self.extension = resourceExtensions
        if let url = metadata.url {
            self.url = url.asFHIRURIPrimitive()
        }
        self.version = metadata.version?.asFHIRStringPrimitive()
        self.title = metadata.title.isEmpty ? nil : metadata.title.asFHIRStringPrimitive()
        self.name = metadata.title.isEmpty ? nil : metadata.title
            .components(separatedBy: .alphanumerics.inverted).joined().asFHIRStringPrimitive()
        self.description_fhir = metadata.explainer.isEmpty ? nil : metadata.explainer.asFHIRStringPrimitive()
        self.publisher = metadata.publisher?.asFHIRStringPrimitive()
        self.copyright = metadata.copyright?.asFHIRStringPrimitive()
    }
}


extension ModelsR4.Extension {
    /// The abbreviated title constrained displays fall back to (SDC `shortText`).
    static func shortText(_ shortTitle: String) -> Extension {
        Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText",
            value: .string(shortTitle.asFHIRStringPrimitive())
        )
    }
}
