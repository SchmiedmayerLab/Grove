//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Identifiers minted before the rename to Grove.
///
/// Every string here names data that already exists on a user's device. None of them may change.
/// They live in one target so the rest of the codebase contains no pre-Grove name at all, and so
/// they can be deleted wholesale once their migrations have shipped.
///
/// Nothing here is marked deprecated. This target is not a package product, so the only code that can
/// reach these constants is the migrations that are supposed to read them; a deprecation would warn
/// the one caller entitled to call. The transience is enforced by `LegacyIdentifierInventoryTests`
/// instead, which fails when a constant is added or removed without a deliberate edit.
///
/// ## Topics
///
/// ### On-device migration
/// - ``LegacyStorage``
/// - ``LegacyKeychain``
/// - ``LegacyNotifications``
/// ### Diagnostics
/// - ``LegacyIdentifierReport``
public enum GroveLegacyIdentifiers {}
