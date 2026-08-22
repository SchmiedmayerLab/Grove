//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation


struct HealthKitECGSymptomEvidence: Hashable, Sendable {
    let sourceUUID: UUID
    let typeIdentifier: String
    let severityValue: Int
    let startDate: Date
    let endDate: Date
    let timeZone: TimeZone
    let sourceName: String
    let sourceBundleIdentifier: String
    let sourceVersion: String?
    let sourceProductType: String?
    let sourceOperatingSystemMajorVersion: Int
    let sourceOperatingSystemMinorVersion: Int
    let sourceOperatingSystemPatchVersion: Int
}

#endif
