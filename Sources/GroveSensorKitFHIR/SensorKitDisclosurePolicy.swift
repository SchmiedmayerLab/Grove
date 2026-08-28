//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Controls disclosure of SensorKit identifiers that recur across records.
///
/// SensorKit's visit `locationId` is stable across visits to the same place. That recurrence is the
/// whole analytic value — it is what lets a study recognise a participant returning somewhere — and
/// it is also exactly what makes the identifier linkable. The two are the same property, so the
/// choice belongs to the deployment rather than to this adapter.
///
/// This mirrors `HealthKitSourceDisclosurePolicy` with one deliberate difference: an ECG's symptom
/// evidence is *required* by its contract, so omission fails the conversion closed. A visit converts
/// perfectly well without its location, so omission here removes an addition rather than rejecting
/// the record.
public enum SensorKitLinkableIdentifierPolicy: Hashable, Sendable {
    /// Omit identifiers that recur across records. This is the privacy-preserving default.
    case omit
    /// The caller has established necessity and authorization to disclose them.
    case authorized
}
