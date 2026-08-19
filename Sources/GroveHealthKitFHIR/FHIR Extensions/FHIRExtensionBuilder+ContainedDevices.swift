//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import FHIRModelsExtensions
import Foundation
public import HealthKit
import ModelsR4


/// The MDC production-specification codes used for `Device.version.type`
/// (system `urn:iso:std:iso:11073:10101`), per the Personal Health Device IG.
private enum MDCVersionType {
    static let system: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"

    static let hardware = Coding(code: "531974", display: "MDC_ID_PROD_SPEC_HW", system: system)
    static let software = Coding(code: "531975", display: "MDC_ID_PROD_SPEC_SW", system: system)
    static let firmware = Coding(code: "531976", display: "MDC_ID_PROD_SPEC_FW", system: system)
}


private enum GroveDeviceVocabulary {
    static let deviceTypeSystem: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/CodeSystem/grove-device-type"
    static let versionTypeSystem: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/CodeSystem/grove-device-version-type"
    static let recordingMethodSystem: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/CodeSystem/grove-recording-method"
    static let deviceLocalIdSid: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/sid/device-local-id"
    static let appleBundleIdSid: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/sid/apple-bundle-id"

    static let gatewayDeviceExtension: FHIRPrimitive<FHIRURI> = "http://hl7.org/fhir/StructureDefinition/observation-gatewayDevice"
    static let recordingMethodExtension: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/StructureDefinition/grove-recording-method"
    static let inferredValueExtension: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/StructureDefinition/grove-inferred-value"
    static let sensorDeviceProfile: FHIRPrimitive<Canonical> = "https://grovealliance.org/fhir/core/StructureDefinition/grove-sensor-device"
    static let gatewayDeviceProfile: FHIRPrimitive<Canonical> = "https://grovealliance.org/fhir/core/StructureDefinition/grove-gateway-device"
}


/// The `grove-device-type` form factor implied by a device's manufacturer and model.
///
/// Nothing on the HealthKit path reports a form factor: Apple hardware arrives as a
/// hardware-versioned model string (`Watch7,12`, `iPhone17,2`), and a Bluetooth peripheral's
/// model is whatever its Device Information Service put in `modelNumber`. Every answer here
/// is therefore a guess, and is marked as one where it is written.
enum DeviceFormFactor {
    private struct Rule {
        /// Matched against the manufacturer only when the device names one; `nil` matches any.
        let manufacturer: String?
        /// Matched against the whole model as a prefix, or against any word within it.
        let model: String
        let code: String
    }

    /// Apple's model strings match on a prefix; a peripheral only matches when its model
    /// spells the form factor out as a word, which is the only case where a vendor string
    /// says anything reliable. `iPad` and `Mac` are absent on purpose — the value set has
    /// no code for them, and an unrecognized device must stay untyped rather than guessed.
    private static let rules: [Rule] = [
        Rule(manufacturer: "apple", model: "watch", code: "watch"),
        Rule(manufacturer: "apple", model: "iphone", code: "phone"),
        Rule(manufacturer: "apple", model: "realitydevice", code: "head-mounted"),
        Rule(manufacturer: nil, model: "scale", code: "scale"),
        Rule(manufacturer: nil, model: "ring", code: "ring"),
        Rule(manufacturer: nil, model: "band", code: "fitness-band"),
        Rule(manufacturer: nil, model: "tracker", code: "fitness-band"),
        Rule(manufacturer: nil, model: "strap", code: "chest-strap")
    ]

    static func code(manufacturer: String?, model: String?) -> String? {
        guard let model = model?.lowercased(), !model.isEmpty else {
            return nil
        }
        let manufacturer = manufacturer?.lowercased()
        let words = model.split { !$0.isLetter && !$0.isNumber }
        return rules.first { rule in
            // A manufacturer constraint only bites when the device names one: HealthKit
            // leaves the field empty often enough that requiring it would lose the watch.
            guard rule.manufacturer.map({ manufacturer?.hasPrefix($0) ?? true }) ?? true else {
                return false
            }
            return model.hasPrefix(rule.model) || words.contains { $0 == rule.model }
        }?.code
    }

    /// The operating system a gateway's `productType` implies, so its version number
    /// is interpretable as more than a bare "26.0.1".
    static func operatingSystemName(forProductType productType: String?) -> String? {
        switch productType?.lowercased() {
        case let type? where type.hasPrefix("watch"): "watchOS"
        case let type? where type.hasPrefix("iphone") || type.hasPrefix("ipod"): "iOS"
        case let type? where type.hasPrefix("ipad"): "iPadOS"
        case let type? where type.hasPrefix("realitydevice"): "visionOS"
        case let type? where type.hasPrefix("mac"): "macOS"
        default: nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionBuilderProtocol where Self == FHIRExtensionBuilder<HKObject> {
    /// Encodes the sample's `HKDevice` — the hardware that RECORDED the measurement —
    /// as a contained `Device` conforming to the Grove Sensor Device profile,
    /// referenced from `Observation.device`.
    ///
    /// This is the standards-based successor of the retired string-valued `sourceDevice`
    /// extension: consumers get `Device.deviceName`, `manufacturer`, `modelNumber`,
    /// and MDC-coded `version` slices instead of a proprietary extension tree.
    public static var containedSensorDevice: Self {
        .init { object, resource in
            guard var observation = resource as? Observation else {
                return
            }
            guard let hkDevice = object.device else {
                observation.removeContained(id: "sensor-device")
                observation.setFormFactorTag(nil)
                if observation.device?.reference?.value?.string == "#sensor-device" {
                    observation.device = nil
                }
                resource = observation
                return
            }
            let formFactor = DeviceFormFactor.code(manufacturer: hkDevice.manufacturer, model: hkDevice.model)
            let device = Self.sensorDevice(hkDevice, formFactor: formFactor)
            // The same fact on `meta.tag`, where `_tag` can reach it: a contained Device
            // is invisible to search. An unknown form factor is left untagged rather than
            // tagged `unknown`, so "not a watch" and "we don't know" stay distinguishable.
            observation.setFormFactorTag(formFactor)
            observation.replaceContained(device: device, id: "sensor-device")
            observation.device = Reference(reference: "#sensor-device")
            resource = observation
        }
    }

    /// Encodes the sample's `HKSourceRevision` — the app-and-OS environment that SAVED
    /// the sample — as a contained `Device` conforming to the Grove Gateway Device
    /// profile, linked via the HL7 `observation-gatewayDevice` extension.
    ///
    /// This is the standards-based successor of the retired string-valued `sourceRevision`
    /// extension and mirrors the gateway (PHG) role of the Personal Health Device IG.
    public static var containedGatewayDevice: Self {
        .init { object, resource in
            guard var observation = resource as? Observation else {
                return
            }
            guard let device = Self.gatewayDevice(for: object.sourceRevision) else {
                // Nothing the revision told us survived: a Device with only an id says less than no Device at all.
                observation.removeContained(id: "gateway-device")
                observation.removeAllExtensions(withUrl: GroveDeviceVocabulary.gatewayDeviceExtension)
                resource = observation
                return
            }
            observation.replaceContained(device: device, id: "gateway-device")
            observation.append(
                extension: Extension(
                    url: GroveDeviceVocabulary.gatewayDeviceExtension,
                    value: .reference(Reference(reference: "#gateway-device"))
                ),
                behaviour: .replace
            )
            resource = observation
        }
    }

    /// Records how the sample was captured (`grove-recording-method`):
    /// `manual-entry` when HealthKit flags the sample as user-entered, `actively-recorded` when the
    /// sample type only exists because the user started the measurement, and `automatically-recorded`
    /// for the remaining device-attached samples.
    public static var recordingMethod: Self {
        .init { object, resource in
            guard var observation = resource as? Observation else {
                return
            }
            let code: String?
            if (object.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true {
                code = "manual-entry"
            } else if object.device != nil {
                code = object.isUserInitiatedMeasurement ? "actively-recorded" : "automatically-recorded"
            } else {
                code = nil
            }
            observation.removeAllExtensions(withUrl: GroveDeviceVocabulary.recordingMethodExtension)
            if let code {
                observation.append(extension: Extension(
                    url: GroveDeviceVocabulary.recordingMethodExtension,
                    value: .coding(Coding(
                        code: code.asFHIRStringPrimitive(),
                        system: GroveDeviceVocabulary.recordingMethodSystem
                    ))
                ))
            }
            resource = observation
        }
    }

    private static func sensorDevice(_ hkDevice: HKDevice, formFactor: String?) -> Device {
        var device = Device()
        device.id = "sensor-device"
        device.meta = Meta(profile: [GroveDeviceVocabulary.sensorDeviceProfile])
        if let name = hkDevice.name?.nonEmpty {
            let deviceName = DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(DeviceNameType.userFriendlyName)
            )
            device.deviceName = [deviceName]
        }
        device.manufacturer = hkDevice.manufacturer?.nonEmpty?.asFHIRStringPrimitive()
        device.modelNumber = hkDevice.model?.nonEmpty?.asFHIRStringPrimitive()
        device.type = Self.inferredDeviceType(formFactor)
        let versions = Self.versions(of: hkDevice)
        device.version = versions.isEmpty ? nil : versions
        if let localIdentifier = hkDevice.localIdentifier?.nonEmpty {
            device.identifier = [
                Identifier(
                system: GroveDeviceVocabulary.deviceLocalIdSid,
                value: localIdentifier.asFHIRStringPrimitive()
            )
            ]
        }
        if let udi = hkDevice.udiDeviceIdentifier?.nonEmpty {
            var carrier = DeviceUdiCarrier()
            carrier.deviceIdentifier = udi.asFHIRStringPrimitive()
            device.udiCarrier = [carrier]
        }
        return device
    }

    private static func versions(of hkDevice: HKDevice) -> [DeviceVersion] {
        var versions: [DeviceVersion] = []
        if let hardware = hkDevice.hardwareVersion?.nonEmpty {
            versions.append(DeviceVersion(
                type: CodeableConcept(coding: [MDCVersionType.hardware]),
                value: hardware.asFHIRStringPrimitive()
            ))
        }
        if let firmware = hkDevice.firmwareVersion?.nonEmpty {
            versions.append(DeviceVersion(
                type: CodeableConcept(coding: [MDCVersionType.firmware]),
                value: firmware.asFHIRStringPrimitive()
            ))
        }
        if let software = hkDevice.softwareVersion?.nonEmpty {
            versions.append(DeviceVersion(
                type: CodeableConcept(coding: [MDCVersionType.software]),
                value: software.asFHIRStringPrimitive()
            ))
        }
        return versions
    }

    private static func gatewayDevice(for revision: HKSourceRevision) -> Device? {
        var device = Device()
        device.id = "gateway-device"
        device.meta = Meta(profile: [GroveDeviceVocabulary.gatewayDeviceProfile])
        if let name = revision.source.name.nonEmpty {
            device.deviceName = [
                DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(DeviceNameType.userFriendlyName)
            )
            ]
        }
        if let bundleIdentifier = revision.source.bundleIdentifier.nonEmpty {
            device.identifier = [
                Identifier(
                system: GroveDeviceVocabulary.appleBundleIdSid,
                value: bundleIdentifier.asFHIRStringPrimitive()
            )
            ]
        }
        device.modelNumber = revision.productType?.nonEmpty?.asFHIRStringPrimitive()
        device.type = Self.inferredDeviceType(
            DeviceFormFactor.code(manufacturer: "Apple", model: revision.productType)
        )
        let versions = Self.versions(for: revision)
        device.version = versions.isEmpty ? nil : versions
        guard device.deviceName != nil || device.identifier != nil || device.modelNumber != nil || device.version != nil else {
            return nil
        }
        return device
    }

    private static func versions(for revision: HKSourceRevision) -> [DeviceVersion] {
        var versions: [DeviceVersion] = []
        if let appVersion = revision.version?.nonEmpty {
            versions.append(DeviceVersion(
                type: CodeableConcept(coding: [MDCVersionType.software]),
                value: appVersion.asFHIRStringPrimitive()
            ))
        }
        if let osVersion = Self.versionString(revision.operatingSystemVersion) {
            versions.append(DeviceVersion(
                // Which operating system the number belongs to: "26.0.1" alone says
                // nothing about whether it came from a phone or a watch.
                component: DeviceFormFactor.operatingSystemName(forProductType: revision.productType)
                    .map { Identifier(value: $0.asFHIRStringPrimitive()) },
                type: CodeableConcept(coding: [
                    Coding(
                    code: "operating-system",
                    display: "Operating System Version".asFHIRStringPrimitive(),
                    system: GroveDeviceVocabulary.versionTypeSystem
                )
                ]),
                value: osVersion.asFHIRStringPrimitive()
            ))
        }
        return versions
    }

    /// The three-part version string, or nil when the platform reported an implausible one —
    /// a default-constructed `HKSourceRevision` fills these fields with uninitialized memory.
    private static func versionString(_ version: OperatingSystemVersion) -> String? {
        let plausible = 0..<1000
        guard (1..<1000).contains(version.majorVersion),
              plausible.contains(version.minorVersion),
              plausible.contains(version.patchVersion) else {
            return nil
        }
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// The form factor as `Device.type`, flagged as inferred: HealthKit reports none, so
    /// a consumer must be able to tell this apart from a platform that states its own.
    private static func inferredDeviceType(_ code: String?) -> CodeableConcept? {
        guard let code else {
            return nil
        }
        var coding = Coding(
            code: code.asFHIRStringPrimitive(),
            system: GroveDeviceVocabulary.deviceTypeSystem
        )
        coding.extension = [Extension(url: GroveDeviceVocabulary.inferredValueExtension, value: .boolean(true))]
        return CodeableConcept(coding: [coding])
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Observation {
    /// Replaces the contained resource with the given id (containment is per-observation,
    /// so ids are stable well-known values like `sensor-device`).
    fileprivate mutating func replaceContained(device: Device, id: String) {
        var contained = self.contained ?? []
        contained.removeAll { $0.get().id?.value?.string == id }
        contained.append(ResourceProxy(with: device))
        self.contained = contained.isEmpty ? nil : contained
    }

    /// Replaces the recording device's form-factor tag, dropping it entirely when the
    /// form factor is unknown.
    fileprivate mutating func setFormFactorTag(_ code: String?) {
        var tags = (meta?.tag ?? []).filter { $0.system != GroveDeviceVocabulary.deviceTypeSystem }
        if let code {
            tags.append(Coding(
                code: code.asFHIRStringPrimitive(),
                system: GroveDeviceVocabulary.deviceTypeSystem
            ))
        }
        guard !tags.isEmpty || meta?.tag != nil else {
            return
        }
        var meta = self.meta ?? Meta()
        meta.tag = tags.isEmpty ? nil : tags
        self.meta = meta
    }

    fileprivate mutating func removeContained(id: String) {
        let remaining = (contained ?? []).filter { $0.get().id?.value?.string != id }
        contained = remaining.isEmpty ? nil : remaining
    }
}


@available(macOS 13, *)
extension HKObject {
    /// Sample types HealthKit can only produce from a measurement the user deliberately started —
    /// an ECG needs thirty seconds of finger contact, a workout is started by hand.
    @available(iOS 18, macOS 15, watchOS 11, *)
    fileprivate var isUserInitiatedMeasurement: Bool {
        self is HKElectrocardiogram || self is HKWorkout
    }
}


extension String {
    /// The string, unless it is empty or only whitespace: R4's `string` is `[ \r\n\t\S]+`,
    /// so an empty value is a validation error rather than an absent one.
    fileprivate var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

#endif
