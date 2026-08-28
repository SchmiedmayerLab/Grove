//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
public import HealthKit
public import ModelsDSTU2
public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsDSTU2.DomainResource {
    /// Records the HealthKit source revision that produced this resource, as extensions.
    ///
    /// The producing app, its version, and the operating system it ran on are provenance a
    /// consumer needs to interpret the data, and FHIR has no element for them.
    public mutating func addSourceRevisionExtensions(for sourceRevision: HKSourceRevision) {
        let baseUrl: ModelsDSTU2.FHIRPrimitive<ModelsDSTU2.FHIRURI> = FHIRExtensionURL.sourceRevision.dstu2
        var deviceInfo = ModelsDSTU2.Extension(url: baseUrl)
        deviceInfo.extension = []
        let fieldUrl = { (components: String...) -> ModelsDSTU2.FHIRPrimitive<ModelsDSTU2.FHIRURI> in
            // swiftlint:disable:next force_unwrapping
            components.reduce(into: baseUrl.value!.url) { url, component in
                url.append(component: component)
            }
            .asFHIRURIPrimitive()
        }
        let appendDeviceInfoEntry = { (keyPath: KeyPath<HKSourceRevision, String?>) in
            guard let name = keyPath._kvcKeyPathString else {
                print("Unable to obtain name for keyPath '\(keyPath)'. Skipping.")
                return
            }
            guard let value = sourceRevision[keyPath: keyPath] else {
                return
            }
            deviceInfo.extension!.append( // swiftlint:disable:this force_unwrapping
                ModelsDSTU2.Extension(
                    url: fieldUrl(name),
                    value: .string(value.asFHIRStringPrimitive())
                )
            )
        }
        deviceInfo.extension!.append( // swiftlint:disable:this force_unwrapping
            ModelsDSTU2.Extension(
                extension: [
                    ModelsDSTU2.Extension(
                        url: fieldUrl("source", "name"),
                        value: .string(sourceRevision.source.name.asFHIRStringPrimitive())
                    ),
                    ModelsDSTU2.Extension(
                        url: fieldUrl("source", "bundleIdentifier"),
                        value: .string(sourceRevision.source.bundleIdentifier.asFHIRStringPrimitive())
                    )
                ],
                url: fieldUrl("source")
            )
        )
        appendDeviceInfoEntry(\.version)
        appendDeviceInfoEntry(\.productType)
        appendDeviceInfoEntry(\.OSVersion)
        if self.extension == nil {
            self.extension = [deviceInfo]
        } else {
            self.extension!.append(deviceInfo) // swiftlint:disable:this force_unwrapping
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.DomainResource {
    /// Records the HealthKit source revision that produced this resource, as extensions.
    ///
    /// The producing app, its version, and the operating system it ran on are provenance a
    /// consumer needs to interpret the data, and FHIR has no element for them.
    public mutating func addSourceRevisionExtensions(for sourceRevision: HKSourceRevision) {
        let baseUrl: ModelsR4.FHIRPrimitive<ModelsR4.FHIRURI> = FHIRExtensionURL.sourceRevision.r4
        var deviceInfo = ModelsR4.Extension(url: baseUrl)
        deviceInfo.extension = []
        let fieldUrl = { (components: String...) -> ModelsR4.FHIRPrimitive<ModelsR4.FHIRURI> in
            // swiftlint:disable:next force_unwrapping
            components.reduce(into: baseUrl.value!.url) { url, component in
                url.append(component: component)
            }
            .asFHIRURIPrimitive()
        }
        let appendDeviceInfoEntry = { (keyPath: KeyPath<HKSourceRevision, String?>) in
            guard let name = keyPath._kvcKeyPathString else {
                print("Unable to obtain name for keyPath '\(keyPath)'. Skipping.")
                return
            }
            guard let value = sourceRevision[keyPath: keyPath] else {
                return
            }
            deviceInfo.extension!.append( // swiftlint:disable:this force_unwrapping
                ModelsR4.Extension(
                    url: fieldUrl(name),
                    value: .string(value.asFHIRStringPrimitive())
                )
            )
        }
        deviceInfo.extension!.append( // swiftlint:disable:this force_unwrapping
            ModelsR4.Extension(
                extension: [
                    ModelsR4.Extension(
                        url: fieldUrl("source", "name"),
                        value: .string(sourceRevision.source.name.asFHIRStringPrimitive())
                    ),
                    ModelsR4.Extension(
                        url: fieldUrl("source", "bundleIdentifier"),
                        value: .string(sourceRevision.source.bundleIdentifier.asFHIRStringPrimitive())
                    )
                ],
                url: fieldUrl("source")
            )
        )
        appendDeviceInfoEntry(\.version)
        appendDeviceInfoEntry(\.productType)
        appendDeviceInfoEntry(\.OSVersion)
        if self.extension == nil {
            self.extension = [deviceInfo]
        } else {
            self.extension!.append(deviceInfo) // swiftlint:disable:this force_unwrapping
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKSourceRevision {
    /// We define this as an optional String objc-compatible property, so that we can encode it into an Extension using the API we have above.
    @objc fileprivate var OSVersion: String? {
        let version = operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionURL {
    /// The encoded `HKSourceRevision` of the object a resource was created from.
    ///
    /// Only clinical records still carry this: for every sample the Grove adapter converts, the
    /// authoring application or device is a Device in the conversion graph instead.
    static let sourceRevision = Self("https://myheartcounts.stanford.edu/fhir/core/sourceRevision")
}
