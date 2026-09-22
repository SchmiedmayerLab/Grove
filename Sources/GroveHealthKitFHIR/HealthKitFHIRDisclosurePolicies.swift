//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)


/// Controls disclosure of globally identifying recording-device information.
///
/// Selecting ``authorizedUDI`` is an explicit caller attestation that disclosing the
/// HealthKit UDI is necessary for the deployment and has been authorized.
public enum HealthKitUDIDisclosurePolicy: Hashable, Sendable {
    /// Omit globally identifying device information. This is the privacy-preserving default.
    case omit
    /// Disclose the UDI supplied by HealthKit after the caller has established necessity
    /// and authorization.
    case authorizedUDI
}


/// Interpretation of `HKSourceRevision.source` for one conversion.
///
/// Which application wrote a sample is provenance a study needs — a weight from a connected scale
/// is different evidence from one typed in by hand — so the writer is always recorded. An
/// `HKSource` always carries a bundle identifier and is an application; hardware attribution is
/// `HKDevice`, which the recording device carries separately.
public enum HealthKitWriter: Hashable, Sendable {
    /// Record the writer as the application it is. This is the default.
    case application
    /// The caller has established that the source stands for a device rather than an application.
    /// The Provenance author reuses the dual-identity recording Device when stable per-unit
    /// evidence exists. Without that evidence, the Device author is omitted rather than inferred
    /// from model, product, application, or record identifiers.
    case device
}

#endif
