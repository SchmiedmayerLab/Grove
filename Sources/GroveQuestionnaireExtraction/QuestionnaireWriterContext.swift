//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Darwin
#endif
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// A malformed application or host fact supplied for the Questionnaire writer context.
public enum QuestionnaireWriterContextError: Error, Equatable, Sendable {
    case emptyApplicationName
    case emptyApplicationVersion
    case emptyApplicationBuild
    case emptyHostModel
    case emptyHostOperatingSystemVersion
    case missingApplicationIdentifier
    case missingApplicationName
    case missingApplicationVersion
}


/// Application and host facts captured when a QuestionnaireResponse is authored.
///
/// These are deliberately plain facts rather than Grove Device snapshots. Snapshot identities
/// are scoped to a later exchange event and are created only when that event is assembled.
public struct QuestionnaireWriterContext: Hashable, Sendable {
    /// Canonical URL of the corresponding complex FHIR extension.
    public static let canonicalURL = FHIRPrimitive(FHIRURI(
        stringLiteral: "https://grovealliance.org/fhir/questionnaire/StructureDefinition/grove-questionnaire-writer-context"
    ))

    public let applicationIdentifier: BusinessIdentifier
    public let applicationName: String
    public let applicationVersion: String
    public let applicationBuild: String?
    public let hostModel: String?
    public let hostOperatingSystemVersion: String?

    public init(
        applicationIdentifier: BusinessIdentifier,
        applicationName: String,
        applicationVersion: String,
        applicationBuild: String? = nil,
        hostModel: String? = nil,
        hostOperatingSystemVersion: String? = nil
    ) throws(QuestionnaireWriterContextError) {
        guard !applicationName.isEmpty else {
            throw .emptyApplicationName
        }
        guard !applicationVersion.isEmpty else {
            throw .emptyApplicationVersion
        }
        if applicationBuild?.isEmpty == true {
            throw .emptyApplicationBuild
        }
        if hostModel?.isEmpty == true {
            throw .emptyHostModel
        }
        if hostOperatingSystemVersion?.isEmpty == true {
            throw .emptyHostOperatingSystemVersion
        }
        self.applicationIdentifier = applicationIdentifier
        self.applicationName = applicationName
        self.applicationVersion = applicationVersion
        self.applicationBuild = applicationBuild
        self.hostModel = hostModel
        self.hostOperatingSystemVersion = hostOperatingSystemVersion
    }

    /// Captures facts from the running application and host.
    ///
    /// The identifier namespace remains deployment-owned and must therefore be supplied by the
    /// caller. Tests and retry stores should prefer the explicit initializer so the captured facts
    /// do not change underneath an exchange event.
    public static func current(
        applicationIdentifierSystem: IdentifierSystem,
        bundle: Foundation.Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) throws -> Self {
        guard let bundleIdentifier = bundle.bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw QuestionnaireWriterContextError.missingApplicationIdentifier
        }
        let info = bundle.infoDictionary ?? [:]
        guard let applicationName = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String,
              !applicationName.isEmpty else {
            throw QuestionnaireWriterContextError.missingApplicationName
        }
        guard let applicationVersion = info["CFBundleShortVersionString"] as? String,
              !applicationVersion.isEmpty else {
            throw QuestionnaireWriterContextError.missingApplicationVersion
        }
        let operatingSystemVersion = processInfo.operatingSystemVersion
        return try Self(
            applicationIdentifier: BusinessIdentifier(
                system: applicationIdentifierSystem,
                value: bundleIdentifier
            ),
            applicationName: applicationName,
            applicationVersion: applicationVersion,
            applicationBuild: (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            hostModel: currentHostModel(processInfo: processInfo),
            hostOperatingSystemVersion: [
                operatingSystemVersion.majorVersion,
                operatingSystemVersion.minorVersion,
                operatingSystemVersion.patchVersion
            ].map(String.init).joined(separator: ".")
        )
    }

    private static func currentHostModel(processInfo: ProcessInfo) -> String? {
        if let simulatedModel = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulatedModel.isEmpty {
            return simulatedModel
        }
        #if canImport(Darwin)
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            return nil
        }
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(validatingCString: $0)
            }
        }.flatMap { $0.isEmpty ? nil : $0 }
        #else
        return nil
        #endif
    }
}


extension QuestionnaireWriterContext {
    var fhirExtension: ModelsR4.Extension {
        var children = [
            ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: "applicationIdentifier")),
                value: .identifier(applicationIdentifier.fhirIdentifier)
            ),
            ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: "applicationName")),
                value: .string(applicationName.asFHIRStringPrimitive())
            ),
            ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: "applicationVersion")),
                value: .string(applicationVersion.asFHIRStringPrimitive())
            )
        ]
        if let applicationBuild {
            children.append(ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: "applicationBuild")),
                value: .string(applicationBuild.asFHIRStringPrimitive())
            ))
        }
        if let hostModel {
            children.append(ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: "hostModel")),
                value: .string(hostModel.asFHIRStringPrimitive())
            ))
        }
        if let hostOperatingSystemVersion {
            children.append(ModelsR4.Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: "hostOperatingSystemVersion")),
                value: .string(hostOperatingSystemVersion.asFHIRStringPrimitive())
            ))
        }
        return ModelsR4.Extension(extension: children, url: Self.canonicalURL)
    }
}


extension ModelsR4.QuestionnaireResponse {
    /// Adds or replaces the one Grove Questionnaire writer-context extension.
    public mutating func apply(writerContext: QuestionnaireWriterContext) {
        var extensions = self.extension ?? []
        extensions.removeAll { $0.url == QuestionnaireWriterContext.canonicalURL }
        extensions.append(writerContext.fhirExtension)
        self.extension = extensions
    }
}
