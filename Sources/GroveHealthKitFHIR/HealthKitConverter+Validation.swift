//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Every context check the converter runs before it mints an identifier.

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    static func validate(context: HealthKitConversionContext) throws(HealthKitConversionError) {
        try validateConverterApplication(context)
        try validateRecordingIdentity(context)
        try validateNativeIdentifierDisclosure(context)
        _ = try validateReference(
            reference: context.subject,
            field: "subject",
            expectedResourceType: .patient
        )
        try validateResearchStudies(context.researchStudies)
    }

    private static func validateConverterApplication(
        _ context: HealthKitConversionContext
    ) throws(HealthKitConversionError) {
        // Checked first: an empty bundle identifier still yields a syntactically valid graph
        // namespace (`urn:grove:healthkit-graph:`), so nothing downstream would catch it. A host
        // can carry CFBundleName without CFBundleIdentifier, so the name check would not either.
        guard isValidAppleBundleIdentifier(context.converter.bundleIdentifier) else {
            throw HealthKitConversionError.invalidConverterApplication("bundleIdentifier")
        }
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HealthKitConversionError.invalidConverterApplication("name")
        }
        guard !context.converter.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HealthKitConversionError.invalidConverterApplication("version")
        }
        guard !context.converterHost.sourceDeviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HealthKitConversionError.invalidConverterApplication("converterHost.sourceDeviceToken")
        }
        guard !context.converterHost.operatingSystemVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HealthKitConversionError.invalidConverterApplication("converterHost.operatingSystemVersion")
        }
        for (field, value) in [
            ("converterHost.name", context.converterHost.name),
            ("converterHost.manufacturer", context.converterHost.manufacturer),
            ("converterHost.modelNumber", context.converterHost.modelNumber)
        ] where value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw HealthKitConversionError.invalidConverterApplication(field)
        }
    }

    private static func validateRecordingIdentity(
        _ context: HealthKitConversionContext
    ) throws(HealthKitConversionError) {
        if context.recordingDeviceStableUnitToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw HealthKitConversionError.invalidExchangeIdentity(
                "recordingDeviceStableUnitToken must be absent or nonempty"
            )
        }
    }

    private static func validateNativeIdentifierDisclosure(
        _ context: HealthKitConversionContext
    ) throws(HealthKitConversionError) {
        if case let .authorized(nativeSystem, _) = context.nativeIdentifierDisclosurePolicy {
            let reservedSystems = Set(context.identityScope.systems.all + [
                context.eventIdentifier.businessIdentifier.system,
                context.entryNodeIdentifierSystem
            ])
            guard !reservedSystems.contains(nativeSystem) else {
                throw HealthKitConversionError.invalidExchangeIdentity(
                    "native HealthKit identifier system must not reuse a Grove graph identity system"
                )
            }
        }
    }

    private static func validateResearchStudies(
        _ researchStudies: [Reference]
    ) throws(HealthKitConversionError) {
        var studyIdentities: Set<TypedReferenceIdentity> = []
        for study in researchStudies {
            let identity = try validateReference(
                reference: study,
                field: "researchStudies",
                expectedResourceType: .researchStudy
            )
            guard studyIdentities.insert(identity).inserted else {
                throw HealthKitConversionError.duplicateReference(field: "researchStudies")
            }
        }
    }

    static func isValidAppleBundleIdentifier(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("."),
              !value.hasSuffix("."),
              !value.contains("..") else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            (0x41...0x5A).contains(byte)
                || (0x61...0x7A).contains(byte)
                || (0x30...0x39).contains(byte)
                || byte == 0x2D
                || byte == 0x2E
        }
    }

    private static func validateReference(
        reference: Reference,
        field: String,
        expectedResourceType: ResourceType
    ) throws(HealthKitConversionError) -> TypedReferenceIdentity {
        do {
            return try TypedReference.validate(
                reference,
                expectedResourceType: expectedResourceType
            )
        } catch {
            switch error {
            case .literalRequiresBundleEntry:
                throw .invalidExchangeIdentity(
                    TypedReference.literalRefusal(field: field)
                )
            case .invalidReference:
                throw .invalidReference(field: field, expectedResourceType: expectedResourceType)
            }
        }
    }
}

#endif
