//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKSample {
    /// Gets the `TimeZone` from the sample's metadata if available
    /// - Returns: A `TimeZone` if the metadata contains a valid HKMetadataKeyTimeZone value, otherwise nil
    internal var timeZone: TimeZone? {
        guard let timeZoneIdentifier = metadata?[HKMetadataKeyTimeZone] as? String else {
            return nil
        }
        return TimeZone(identifier: timeZoneIdentifier)
    }
}

#endif


#if canImport(HealthKit)
import FHIRModelsExtensions
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension Observation {
    /// Attaches the HL7 `timezone` extension (the IANA zone identifier) to the
    /// effective element, preserving the named zone the offset alone cannot carry.
    mutating func attachTimeZoneExtension(identifier: String) {
        let timeZoneExtension = Extension(
            url: "http://hl7.org/fhir/StructureDefinition/timezone",
            value: .code(FHIRPrimitive(FHIRString(identifier)))
        )
        // Replacing rather than appending: an element carries one zone, and rerunning the
        // conversion over an existing Observation must not accumulate copies.
        switch effective {
        case .dateTime(var primitive):
            primitive.append(extension: timeZoneExtension, behaviour: .replace)
            effective = .dateTime(primitive)
        case .period(var period):
            if var start = period.start {
                start.append(extension: timeZoneExtension, behaviour: .replace)
                period.start = start
            }
            if var end = period.end {
                end.append(extension: timeZoneExtension, behaviour: .replace)
                period.end = end
            }
            effective = .period(period)
        default:
            break
        }
    }
}
#endif
