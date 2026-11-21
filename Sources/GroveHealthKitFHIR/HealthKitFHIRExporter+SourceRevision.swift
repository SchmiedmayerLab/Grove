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
    /// so a retry stays an exact retry. A fact not among `facts` is left out as well, and a revision with no member
    /// left states nothing. Without any fact among `facts`, the whole extension is withheld.
    ///
    /// Apart from withholding the whole extension, the guide lets a policy withhold `sourceBundleIdentifier` only where
    /// it is a ``HealthKitFHIRExporter/SourceFact/deviceBundleIdentifier`` (healthkit mapping.md, source revision): any
    /// other bundle identifier, such as an application's, is stated whenever the extension is.
    static func sourceRevision(
        _ revision: HKSourceRevision,
        facts: Set<HealthKitFHIRExporter.SourceFact>
    ) -> Extension? {
        guard !facts.isEmpty, !revision.source.name.isEmpty || !revision.source.bundleIdentifier.isEmpty else {
            return nil
        }
        var members: [Extension] = []
        func append(_ fact: HealthKitFHIRExporter.SourceFact?, named name: String, value: String?) {
            guard let value, !value.isEmpty, fact.map({ facts.contains($0) }) ?? true else {
                return
            }
            members.append(Extension(url: FHIRPrimitive(FHIRURI(stringLiteral: name)), value: .string(value.asFHIRStringPrimitive())))
        }
        append(.name, named: "sourceName", value: revision.source.name)
        let bundleIdentifier = revision.source.bundleIdentifier
        append(.deviceBundleIdentifierFact(of: bundleIdentifier), named: "sourceBundleIdentifier", value: bundleIdentifier)
        append(.version, named: "version", value: revision.version)
        append(.productType, named: "productType", value: revision.productType)
        let version = revision.operatingSystemVersion
        append(.operatingSystemVersion, named: "operatingSystemVersion", value: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        guard !members.isEmpty else {
            return nil
        }
        return Extension(
            extension: members,
            url: "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-source-revision"
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.SourceFact {
    /// What every ``deviceBundleIdentifier`` starts with; a UUID follows.
    private static let deviceBundleIdentifierPrefix = "com.apple.health."

    /// ``deviceBundleIdentifier`` when `bundleIdentifier` is exactly `com.apple.health.` followed by a UUID in the
    /// 8-4-4-4-12 hexadecimal form, in either case; `nil` for any other bundle identifier, which no policy decides.
    fileprivate static func deviceBundleIdentifierFact(of bundleIdentifier: String) -> Self? {
        guard bundleIdentifier.hasPrefix(deviceBundleIdentifierPrefix) else {
            return nil
        }
        let uuid = Array(bundleIdentifier.utf8.dropFirst(deviceBundleIdentifierPrefix.utf8.count))
        guard uuid.count == 36 else {
            return nil
        }
        let isUUID = uuid.indices.allSatisfy { index in
            [8, 13, 18, 23].contains(index) ? uuid[index] == 0x2D : uuid[index] < 0x80 && Character(UnicodeScalar(uuid[index])).isHexDigit
        }
        return isUUID ? .deviceBundleIdentifier : nil
    }
}

#endif
