//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The policies are ordered by what they govern rather than by kind.
// swiftlint:disable file_types_order


#if canImport(HealthKit)


/// Interpretation of `HKSourceRevision.source` for one conversion.
///
/// Which application wrote a sample is provenance a study needs — a weight from a connected scale
/// is different evidence from one typed in by hand — so the writer is always recorded. An
/// `HKSource` always carries a bundle identifier and is an application; hardware attribution is
/// `HKDevice`, which the recording device carries separately.
public enum HealthKitSourceActor: Hashable, Sendable {
    /// Record the writer as the application it is. This is the default.
    case application
    /// The caller has established that the source stands for a device rather than an application.
    /// The opaque HealthKit source identifier is disclosed only when explicitly authorized.
    case device(discloseIdentifier: Bool)
}


/// Controls disclosure of globally identifying recording-device information.
///
/// Selecting ``authorizedUDI`` is an explicit caller attestation that disclosing the
/// HealthKit UDI is necessary for the deployment and has been authorized. This is
/// independent of the deployment-local identifier namespace configured on
/// ``HealthKitConversionContext``.
public enum HealthKitUDIDisclosurePolicy: Hashable, Sendable {
    /// Omit globally identifying device information. This is the privacy-preserving default.
    case omit
    /// Disclose the UDI supplied by HealthKit after the caller has established necessity
    /// and authorization.
    case authorizedUDI
}


/// Controls disclosure of the complete source revision attached to a correlated ECG symptom.
///
/// The bundle identifier, product type, software version, and operating-system version can
/// be linkable. This policy is therefore independent of recording-device and UDI disclosure.
public enum HealthKitSourceDisclosurePolicy: Hashable, Sendable {
    /// Do not disclose correlated-symptom source revision fields. This is the default.
    /// Because the ECG contract requires those fields, correlated symptoms fail closed.
    case omit
    /// The caller has established necessity and authorization to disclose every required
    /// correlated-symptom `HKSourceRevision` field.
    case authorized
}


/// Controls disclosure of retained metadata that identifies a record across systems.
///
/// `HKSample.metadata` is retained verbatim so a conversion loses nothing, but a handful of its keys
/// carry an identifier another system also holds — an external UUID, a device serial. Those recur
/// across records and link them, which is the same property that makes them useful, so the choice
/// belongs to the deployment rather than to this adapter.
///
/// Omission removes those entries from the retained set and leaves every other entry untouched.
public enum HealthKitLinkableMetadataPolicy: Hashable, Sendable {
    /// Omit metadata entries that identify a record across systems. This is the default.
    case omit
    /// The caller has established necessity and authorization to retain them.
    case authorized
}


/// Controls disclosure of a workout's recorded route.
///
/// A route is a sequence of positions over time. It re-identifies more readily than any other
/// HealthKit series — a home, a workplace, and a daily pattern are recoverable from one week of
/// tracks — and no aggregate substitutes for it when the study needs the path. Because the two are
/// the same property, the choice belongs to the deployment rather than to this adapter.
///
/// Omission drops the route recording and keeps the workout: a session converts perfectly well
/// without its path, so refusing the route removes an addition rather than rejecting the workout.
public enum HealthKitRouteDisclosurePolicy: Hashable, Sendable {
    /// Omit recorded routes. This is the privacy-preserving default.
    case omit
    /// The caller has established necessity and authorization to disclose them.
    case authorized
}

#endif
