//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Identifiers minted before the rename to Grove.
///
/// Every string here names data that already exists — on a user's device, or inside a FHIR resource
/// in someone else's database. None of them may change. They live in one target so the rest of the
/// codebase contains no pre-Grove name at all, and so the transitional half can be deleted wholesale
/// once its migrations have shipped.
///
/// There are two lifetimes, kept in separate directories:
///
/// - `Transitional/` — read once, migrated, then never again. Deleted along with the migrations that
///   consume them, no earlier than one minor release after 0.2.0.
/// - `Published/` — written into FHIR resources that left the device. Read forever, never deleted.
///
/// Nothing here is marked deprecated. This target is not a package product, so the only code that can
/// reach these constants is the migrations that are supposed to read them; a deprecation would warn
/// the one caller entitled to call. The transience is enforced by `LegacyIdentifierInventoryTests`
/// instead, which fails when a constant is added or removed without a deliberate edit.
///
/// ## Topics
///
/// ### Transitional
/// - ``LegacyStorage``
/// - ``LegacyKeychain``
/// - ``LegacyNotifications``
///
/// ### Published
/// - ``SupersededFHIRURLs``
///
/// ### Diagnostics
/// - ``LegacyIdentifierReport``
public enum GroveLegacyIdentifiers {}
