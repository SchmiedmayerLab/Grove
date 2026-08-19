//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import FHIRModelsExtensions
public import HealthKit
public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKSample {
    /// A `ResourceProxy` containing an FHIR  `Observation` based on the concrete subclass of `HKSample`.
    ///
    /// - parameter mapping: A mapping to map `HKSample`s to corresponding FHIR observations allowing the customization of, e.g., codings and units. See ``SampleTypesFHIRMapping``.
    /// - parameter issuedDate: `Instant` specifying when this version of the resource was made available. Defaults to `Date.now`.
    /// - parameter subject: The patient the sample was recorded for. Required: the Grove Mobile Sensor Observation profile
    ///     stamped onto every produced resource pins `subject` to 1..1, as does FHIR's own vital-signs profile.
    /// - parameter extensions: Any `FHIRExtensionBuilder`s that should be applied to each of the produced observations.
    ///     The `FHIRExtensionBuilder.containedSensorDevice`, `FHIRExtensionBuilder.containedGatewayDevice`, `FHIRExtensionBuilder.recordingMethod`, and `FHIRExtensionBuilder.metadata(excluding:)` extension builders are always enabled when creating a FHIR `Observation` from a `HKSample`.
    /// - returns: A `ResourceProxy`containing an FHIR  `Observation` based on the concrete subclass of `HKSample`.
    /// - throws: If a specific `HKSample` type is not supported, or if the sample for some reason cannot be turned into a FHIR resource
    ///     (e.g., because it contains values that cannot be represented using the FHIR types)
    ///
    /// - Important: When mapping an array of HKSample objects into ResourceProxies, for performance reasons always prefer ``Swift/Sequence/mapIntoResourceProxies(using:issuedDate:subject:extensions:)`` or ``Swift/Sequence/compactMapIntoResourceProxies(using:issuedDate:subject:extensions:)``.
    public func resource(
        withMapping mapping: SampleTypesFHIRMapping = .default,
        issuedDate: FHIRPrimitive<Instant>? = nil,
        subject: Reference,
        extensions: [any FHIRExtensionBuilderProtocol] = []
    ) throws -> ResourceProxy {
        #if !os(watchOS)
        if let self = self as? HKClinicalRecord {
            // NOTE: this currently completely circumvents the extension builders.
            // might wanna look into possibly fixig that at some point.
            return try self.resource()
        }
        #endif
        var observation = Observation(
            code: CodeableConcept(),
            status: FHIRPrimitive(.final)
        )
        // Self-declare the profile so validators and profile-aware stores pick up
        // the contract without out-of-band knowledge. `meta.source` names the acquisition
        // channel — one URI per platform, never per app instance, so `_source` stays a
        // filter over channels rather than a second copy of the gateway device.
        observation.meta = Meta(
            profile: [
                FHIRPrimitive(Canonical(
                "https://grovealliance.org/fhir/core/StructureDefinition/grove-mobile-sensor-observation"
            ))
            ],
            source: "https://grovealliance.org/fhir/source/healthkit"
        )
        // Set basic elements applicable to all observations
        observation.id = self.uuid.uuidString.asFHIRStringPrimitive()
        // The identifier carries the platform record id under its own identifier system,
        // so consumers can deduplicate re-uploads without guessing.
        observation.append(identifier: Identifier(
            system: "https://grovealliance.org/fhir/sid/healthkit-sample-id",
            value: observation.id
        ))
        observation.subject = subject
        try applyTimestamps(to: &observation, issuedDate: issuedDate)
        if let self = self as? any FHIRObservationBuildable {
            try self.build(&observation, mapping: mapping)
        } else {
            throw GroveHealthKitFHIRError.notSupported
        }
        // Layer-3 components carry the metadata key they were promoted from, so the Layer-4 envelope
        // skips exactly what the conversion consumed instead of a list it has to keep in sync.
        let promotedKeys = Set((observation.component ?? [])
            .flatMap { $0.code.coding ?? [] }
            .filter { $0.system == GroveFHIRVocabulary.healthKitMetadataKey }
            .compactMap { $0.code?.value?.string })
        // The recording device and saving app are modeled as contained Devices
        // (Observation.device and the observation-gatewayDevice extension) per the
        // Grove FHIR IG, superseding the string-valued sourceDevice/sourceRevision
        // extensions.
        let baseExtensions: [FHIRExtensionBuilder<HKObject>] = [
            .containedSensorDevice, .containedGatewayDevice, .recordingMethod, .metadata(excluding: promotedKeys)
        ]
        for builder in baseExtensions + extensions {
            try builder.apply(typeErasedInput: self, to: &observation)
        }
        return ResourceProxy(with: observation)
    }

    private func applyTimestamps(to observation: inout Observation, issuedDate: FHIRPrimitive<Instant>?) throws {
        // R4 requires an offset on a dateTime carrying a time, so one is always written; only the
        // named zone below is a claim about where the sample was recorded.
        try observation.setEffective(
            startDate: self.startDate,
            endDate: self.endDate,
            timeZone: self.timeZone ?? .current
        )
        if let namedZone = self.timeZone {
            // The offset in effective[x] loses the named zone; the HL7 timezone
            // extension preserves it when the sample's metadata declares one.
            observation.attachTimeZoneExtension(identifier: namedZone.identifier)
        }
        if let issuedDate {
            observation.issued = issuedDate
        } else {
            try observation.setIssued(on: Date())
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Sequence where Element: HKSample {
    /// Produces an Array of FHIR `ResourceProxies`.
    ///
    /// - Note: This method provides significant performance improvements as compared to calling ``HealthKit/HKSample/resource(withMapping:issuedDate:subject:extensions:)`` for each element in the collection.
    ///
    /// - parameter mapping: A mapping to map `HKSample`s to corresponding FHIR observations allowing the customization of, e.g., codings and units. See ``SampleTypesFHIRMapping``.
    /// - parameter issuedDate: `Instant` specifying when this version of the resource was made available. Defaults to `Date.now`.
    /// - parameter subject: The patient the samples were recorded for.
    /// - parameter extensions: Any `FHIRExtensionBuilder`s that should be applied to each of the produced observations.
    ///     The `FHIRExtensionBuilder.containedSensorDevice`, `FHIRExtensionBuilder.containedGatewayDevice`, `FHIRExtensionBuilder.recordingMethod`, and `FHIRExtensionBuilder.metadata(excluding:)` extension builders are always enabled when creating a FHIR `Observation` from a `HKSample`.
    public func mapIntoResourceProxies(
        using mapping: SampleTypesFHIRMapping = .default,
        issuedDate: FHIRPrimitive<Instant>? = nil,
        subject: Reference,
        extensions: [any FHIRExtensionBuilderProtocol] = []
    ) throws -> [ResourceProxy] {
        let issuedDate = try issuedDate ?? FHIRPrimitive<Instant>(try Instant(date: .now))
        return try map { try $0.resource(withMapping: mapping, issuedDate: issuedDate, subject: subject, extensions: extensions) }
    }
    
    /// Produces an Array of FHIR `ResourceProxies`.
    ///
    /// This function is equivalent to calling ``HealthKit/HKSample/resource(withMapping:issuedDate:subject:extensions:)`` on every element in the sequence, and filtering out those elements for which the call raised an error.
    ///
    /// - Note: This method provides significant performance improvements as compared to calling ``HealthKit/HKSample/resource(withMapping:issuedDate:subject:extensions:)`` on each element in the collection.
    ///
    /// - parameter mapping: A mapping to map `HKSample`s to corresponding FHIR observations allowing the customization of, e.g., codings and units. See ``SampleTypesFHIRMapping``.
    /// - parameter issuedDate: `Instant` specifying when this version of the resource was made available. Defaults to `Date.now`.
    /// - parameter subject: The patient the samples were recorded for.
    /// - parameter extensions: Any `FHIRExtensionBuilder`s that should be applied to each of the produced observations.
    ///     The `FHIRExtensionBuilder.containedSensorDevice`, `FHIRExtensionBuilder.containedGatewayDevice`, `FHIRExtensionBuilder.recordingMethod`, and `FHIRExtensionBuilder.metadata(excluding:)` extension builders are always enabled when creating a FHIR `Observation` from a `HKSample`.
    public func compactMapIntoResourceProxies(
        using mapping: SampleTypesFHIRMapping = .default,
        issuedDate: FHIRPrimitive<Instant>? = nil,
        subject: Reference,
        extensions: [any FHIRExtensionBuilderProtocol] = []
    ) throws -> [ResourceProxy] {
        let issuedDate = try issuedDate ?? FHIRPrimitive<Instant>(try Instant(date: .now))
        return compactMap { try? $0.resource(withMapping: mapping, issuedDate: issuedDate, subject: subject, extensions: extensions) }
    }
}

#endif
