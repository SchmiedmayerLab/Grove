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

import Foundation
public import GroveFHIRContract


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
    /// The Provenance author reuses the dual-identity recording Device when stable per-unit
    /// evidence exists. Without that evidence, the Device author is omitted rather than inferred
    /// from model, product, application, or record identifiers.
    case device
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


/// HealthKit spelling of Grove's shared governed source-identifier type.
public typealias HealthKitNativeIdentifierType = GovernedSourceIdentifierType


/// Controls intentional disclosure of the source `HKObject.uuid` on the primary output.
///
/// Grove's opaque `source-record` and `source-output` identifiers remain mandatory and are the
/// protocol identities. This optional identifier exists only for deployments with a governed
/// HealthKit-store namespace and a concrete round-trip or traceability requirement. Grove emits
/// `HKObject.uuid` in canonical lowercase RFC 4122 text, so the supplied `Identifier.system` must
/// name that exact canonical source-store key space. The policy never
/// authorizes copying the UUID into `Resource.id`, filenames, URLs, titles, logs, metadata
/// components, workout children, or supporting resources.
public typealias HealthKitNativeIdentifierDisclosurePolicy = GovernedSourceIdentifierDisclosurePolicy // swiftlint:disable:this type_name


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
