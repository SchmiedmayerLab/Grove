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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    /// The guide's five ordered source-revision members, of which a string fact HealthKit does not supply, or supplies
    /// empty, is left out. This describes the record without classifying its writer.
    ///
    /// A sample the store never held has no revision, although the SDK declares one: its strings read empty, and its
    /// operating-system version is whatever the stack holds. A revision that names no source therefore states nothing,
    /// so a retry stays an exact retry.
    static func sourceRevision(_ revision: HKSourceRevision) -> Extension? {
        guard !revision.source.name.isEmpty || !revision.source.bundleIdentifier.isEmpty else {
            return nil
        }
        var members: [Extension] = []
        func append(named name: String, value: String?) {
            guard let value, !value.isEmpty else {
                return
            }
            members.append(Extension(url: FHIRPrimitive(FHIRURI(stringLiteral: name)), value: .string(value.asFHIRStringPrimitive())))
        }
        append(named: "sourceName", value: revision.source.name)
        append(named: "sourceBundleIdentifier", value: revision.source.bundleIdentifier)
        append(named: "version", value: revision.version)
        append(named: "productType", value: revision.productType)
        let version = revision.operatingSystemVersion
        append(named: "operatingSystemVersion", value: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        return Extension(
            extension: members,
            url: "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-source-revision"
        )
    }
}

#endif
