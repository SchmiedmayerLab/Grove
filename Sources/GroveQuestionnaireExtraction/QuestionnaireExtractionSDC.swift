//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4


/// The SDC and Grove extension URLs the observation extraction reads.
///
/// The SDC URLs are published by `hl7.fhir.uv.sdc` and the unit URLs by the R4 extensions pack;
/// the writer context is Grove's own. None of them are part of the generated catalog contract,
/// which covers Grove-published artifacts only.
enum ExtractionCanonical {
    static let observationExtract = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observationExtract"
    static let observationExtractCategory =
        "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observation-extract-category"
    static let questionnaireUnit = "http://hl7.org/fhir/StructureDefinition/questionnaire-unit"
}


/// How one marked item relates to the Observation its parent extracts to.
enum ExtractionMarking: Equatable {
    /// `valueBoolean true`: the item extracts as its own Observation.
    case standalone
    /// `valueCode component`: the child lands on the parent Observation as a component.
    case component
    /// `valueCode member`: the child extracts separately and the parent links it through `hasMember`.
    case member
    /// `valueCode derived`: the child extracts separately and links back through `derivedFrom`.
    case derived
    /// `valueCode independent`: the child extracts separately with no link to the parent.
    case independent
}


/// Accumulates the writer-context child extensions into the typed fields they carry.
private struct WriterContextFields {
    var applicationIdentifier: BusinessIdentifier?
    var name: String?
    var version: String?
    var build: String?
    var hostModel: String?
    var hostOperatingSystemVersion: String?

    private static func businessIdentifier(_ identifier: Identifier) -> BusinessIdentifier? {
        guard let system = identifier.system?.value?.url.absoluteString,
              let value = identifier.value?.value?.string else {
            return nil
        }
        return try? BusinessIdentifier(system: IdentifierSystem(system), value: value)
    }

    mutating func absorb(_ part: Extension) {
        let field = part.url.value?.url.absoluteString ?? ""
        if field == "applicationIdentifier", case .identifier(let identifier) = part.value {
            applicationIdentifier = Self.businessIdentifier(identifier)
            return
        }
        guard case .string(let value) = part.value else {
            return
        }
        switch field {
        case "applicationName": name = value.value?.string
        case "applicationVersion": version = value.value?.string
        case "applicationBuild": build = value.value?.string
        case "hostModel": hostModel = value.value?.string
        case "hostOperatingSystemVersion": hostOperatingSystemVersion = value.value?.string
        default: break
        }
    }

    func context() -> QuestionnaireWriterContext? {
        guard let applicationIdentifier, let name, let version else {
            return nil
        }
        return try? QuestionnaireWriterContext(
            applicationIdentifier: applicationIdentifier,
            applicationName: name,
            applicationVersion: version,
            applicationBuild: build,
            hostModel: hostModel,
            hostOperatingSystemVersion: hostOperatingSystemVersion
        )
    }
}


extension ModelsR4.Element {
    fileprivate func markerExtensions(url: String) -> [Extension] {
        `extension`?.filter { $0.url.value?.url.absoluteString == url } ?? []
    }
}


extension ModelsR4.DomainResource {
    fileprivate func markerExtensions(url: String) -> [Extension] {
        `extension`?.filter { $0.url.value?.url.absoluteString == url } ?? []
    }
}


extension ModelsR4.QuestionnaireItem {
    /// Every category the item declares for its extracted Observation.
    var extractionCategories: [CodeableConcept] {
        markerExtensions(url: ExtractionCanonical.observationExtractCategory).compactMap { marker in
            if case .codeableConcept(let concept) = marker.value {
                return concept
            }
            return nil
        }
    }

    /// The fixed unit an integer or decimal item is answered in.
    var fixedUnit: Coding? {
        for marker in markerExtensions(url: ExtractionCanonical.questionnaireUnit) {
            if case .coding(let coding) = marker.value {
                return coding
            }
        }
        return nil
    }

    /// The extraction marking, or nil when the item does not participate in extraction.
    ///
    /// SDC declares boolean and code forms and forbids both on one item; contradictory markings
    /// are a refusal rather than a silent choice.
    func extractionMarking() throws(ObservationExtractionError) -> ExtractionMarking? {
        let markers = markerExtensions(url: ExtractionCanonical.observationExtract)
        guard let marker = markers.first else {
            return nil
        }
        guard markers.count == 1 else {
            throw .contradictoryExtractionMarking(linkID: linkId.value?.string ?? "")
        }
        switch marker.value {
        case .boolean(let flag):
            return flag.value?.bool == true ? .standalone : nil
        case .code(let code):
            switch code.value?.string {
            case "component": return .component
            case "member": return .member
            case "derived": return .derived
            case "independent": return .independent
            default:
                throw .contradictoryExtractionMarking(linkID: linkId.value?.string ?? "")
            }
        default:
            throw .contradictoryExtractionMarking(linkID: linkId.value?.string ?? "")
        }
    }
}


extension ModelsR4.QuestionnaireResponse {
    /// Reads the writer context the response carries, or nil when it states none.
    func writerContext() throws(ObservationExtractionError) -> QuestionnaireWriterContext? {
        let url = QuestionnaireWriterContext.canonicalURL.value?.url.absoluteString ?? ""
        guard let marker = markerExtensions(url: url).first else {
            return nil
        }
        var fields = WriterContextFields()
        for part in marker.extension ?? [] {
            fields.absorb(part)
        }
        guard let context = fields.context() else {
            throw .incompleteWriterContext
        }
        return context
    }
}
