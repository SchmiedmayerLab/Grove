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
extension HealthKitFHIRExporter {
    /// Facts disclosed about a source that is not represented by an author agent. An empty set withholds the
    /// entire extension. Names may identify a person or a device, so authorizing them is a deployment decision.
    public struct SourceRevisionFields: OptionSet, Sendable {
        public static let sourceName = Self(rawValue: 1 << 0)
        public static let sourceBundleIdentifier = Self(rawValue: 1 << 1)
        public static let version = Self(rawValue: 1 << 2)
        public static let productType = Self(rawValue: 1 << 3)
        public static let operatingSystemVersion = Self(rawValue: 1 << 4)

        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.SourceRevisionFields: ExchangeContextFingerprinted {
    package var fingerprintParts: [String] { [String(rawValue)] }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    /// The guide's ordered source-revision members. This describes the record without classifying its writer.
    static func sourceRevision(_ revision: HKSourceRevision, fields: HealthKitFHIRExporter.SourceRevisionFields) -> Extension? {
        var members: [Extension] = []
        func append(_ field: HealthKitFHIRExporter.SourceRevisionFields, named name: String, value: String?) {
            guard fields.contains(field), let value, !value.isEmpty else {
                return
            }
            members.append(Extension(url: FHIRPrimitive(FHIRURI(stringLiteral: name)), value: .string(value.asFHIRStringPrimitive())))
        }
        append(.sourceName, named: "sourceName", value: revision.source.name)
        append(.sourceBundleIdentifier, named: "sourceBundleIdentifier", value: revision.source.bundleIdentifier)
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

#endif
