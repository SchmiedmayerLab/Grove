//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreFoundation
import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    static func applySyncIdentity(
        of sample: HKSample,
        to observation: inout Observation,
        context: HealthKitConversionContext
    ) throws {
        try applySyncIdentity(
            metadata: sample.metadata,
            writerApplication: sample.sourceRevision.source.bundleIdentifier,
            to: &observation,
            context: context
        )
    }

    // HealthKit itself models the metadata dictionary as absent when an object has no metadata.
    /// Applies Apple's paired sync metadata after validating it independently of source
    /// attribution. Exposed internally so tests can supply the attributable writer that
    /// HealthKit's public sample factories do not let a test construct.
    static func applySyncIdentity(
        metadata: [String: Any]?, // swiftlint:disable:this discouraged_optional_collection
        writerApplication: String,
        to observation: inout Observation,
        context: HealthKitConversionContext
    ) throws {
        let identifierValue = metadata?[HKMetadataKeySyncIdentifier]
        let versionValue = metadata?[HKMetadataKeySyncVersion]
        guard identifierValue != nil || versionValue != nil else {
            return
        }
        guard let syncIdentifier = identifierValue as? String, !syncIdentifier.isEmpty else {
            throw HealthKitConversionError.invalidMetadataValue(key: HKMetadataKeySyncIdentifier)
        }
        guard let versionValue else {
            throw HealthKitConversionError.invalidMetadataValue(key: HKMetadataKeySyncVersion)
        }
        let version = try canonicalSyncVersion(versionValue)

        // The writer is part of the writer-record namespace. A valid pair without an attributable
        // writer remains omitted rather than being assigned to an invented global/empty writer.
        guard !writerApplication.isEmpty else {
            return
        }
        let identity = try context.identityScope.writerRecord(
            writerApplication: BusinessIdentifier(
                system: Canonicals.appleBundleIdentifierSystem,
                value: writerApplication
            ),
            writerRecordID: syncIdentifier
        )
        observation.identifier = (observation.identifier ?? []) + [identity.fhirIdentifier]
        observation.extension = (observation.extension ?? []) + [
            Extension(
                url: Canonicals.writerRecordVersion,
                value: .string(version.asFHIRStringPrimitive())
            )
        ]
    }

    private static func canonicalSyncVersion(_ value: Any) throws -> String {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              var decimal = Decimal(
                  string: number.stringValue,
                  locale: Locale(identifier: "en_US_POSIX")
              ),
              !decimal.isNaN,
              decimal >= 0 else {
            throw HealthKitConversionError.invalidMetadataValue(key: HKMetadataKeySyncVersion)
        }
        var integral = Decimal()
        NSDecimalRound(&integral, &decimal, 0, .down)
        guard integral == decimal else {
            throw HealthKitConversionError.invalidMetadataValue(key: HKMetadataKeySyncVersion)
        }
        return NSDecimalString(&integral, Locale(identifier: "en_US_POSIX"))
    }

    /// Returns the optional caller-governed source-store identifier for the primary output.
    static func nativeIdentifiers(
        for sample: HKSample,
        policy: HealthKitNativeIdentifierDisclosurePolicy
    ) -> [Identifier] {
        [policy.identifier(for: sample.uuid.uuidString.lowercased())].compactMap { $0 }
    }
}

#endif
