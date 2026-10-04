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


/// How the caller classifies the source (`HKSourceRevision.source`) of one sample.
///
/// HealthKit does not say whether a source is an application or a device, so the classification is the
/// caller's: Grove never infers it from the bundle identifier, the source name or the product type. Which
/// physical unit measured the sample is `HKDevice`, which the recording Device carries separately.
public enum HealthKitWriter: Hashable, Sendable {
    /// The source is an application: it is stated with its name, bundle identifier and version, all copied
    /// from the sample's `HKSourceRevision`, and the host it ran on, as the graph's `ExchangeGraphNode.writer`
    /// and `ExchangeGraphNode.writerHost` snapshots and the Provenance author.
    case application
    /// No writer is stated, and the Provenance names no author.
    case omit
}

#endif
