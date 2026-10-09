//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4


extension SensorKitFHIRExporter.Options {
    /// Every stored option and its fingerprint parts, in declaration order. The completeness test compares the
    /// property names with the stored properties ``SensorKitFHIRExporter/Options`` declares.
    var fingerprintParts: [(property: String, parts: [String])] {
        [("nativeIdentifier", nativeIdentifier.fingerprintParts)]
    }
}


extension SensorKitFHIRExporter.Plan {
    /// The record parts of a request: the output count, then every stored property of each drafted output and of the
    /// call's recording device, by name and in declaration order, with resources and identifiers as sorted-key JSON.
    ///
    /// The drafts are everything a graph states from the record and the call, such as the source time zone through
    /// every effective bound, attachment titles, sidecar paths and payload hashes, so other content under a reserved
    /// key mints a new event instead of restating it. The completeness test compares the names with the stored
    /// properties the draft types declare.
    static func contentParts(outputs: [ExchangeOutputDraft], recordingDevice: ExchangeRecordingDeviceDraft?) throws -> [String] {
        var parts = ["outputs", String(outputs.count)]
        for output in outputs {
            parts += try output.contentParts.flatMap { [$0.property] + $0.parts }
        }
        parts += try ["recordingDevice"] + (recordingDevice.map { try $0.contentParts.flatMap { [$0.property] + $0.parts } } ?? ["none"])
        return parts
    }
}


extension ExchangeOutputDraft {
    /// Every stored property and its parts, in declaration order; a property's parts have a fixed count, or a
    /// leading presence tag fixes it, so the framed sequence stays unambiguous.
    var contentParts: [(property: String, parts: [String])] {
        get throws {
            let resourceJSON = switch resource {
            case .observation(let observation): try canonicalJSON(observation)
            case .document(let document): try canonicalJSON(document)
            }
            return [
                ("role", [role]),
                ("discriminator", [discriminator]),
                ("resource", [resourceJSON]),
                ("links", [String(links.rawValue)]),
                ("derivedFromPrimary", [String(derivedFromPrimary)]),
                ("artifactFormatCode", artifactFormatCode.map { ["some", $0] } ?? ["none"]),
                ("clearIdentifiers", [try canonicalJSON(clearIdentifiers)]),
                ("writerRecord", writerRecord.map { ["some", $0.writerApplication, $0.syncIdentifier, $0.version] } ?? ["none"]),
                ("wasUserEntered", [String(wasUserEntered)]),
                ("trailingExtensions", [try canonicalJSON(trailingExtensions)])
            ]
        }
    }
}


extension ExchangeRecordingDeviceDraft {
    /// Every stored property and its parts, in declaration order: the device's token, which keys its identities, and
    /// its optional facts, then the Device body.
    var contentParts: [(property: String, parts: [String])] {
        get throws {
            let optional = { (value: String?) in value.map { ["some", $0] } ?? ["none"] }
            return [
                ("device", [device.stableUnitToken] + optional(device.name) + optional(device.manufacturer) + optional(device.modelNumber)),
                ("resource", [try canonicalJSON(resource)])
            ]
        }
    }
}


/// The value as sorted-key JSON text.
private func canonicalJSON(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
