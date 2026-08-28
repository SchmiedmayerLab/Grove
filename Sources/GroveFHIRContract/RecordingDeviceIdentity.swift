//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation


/// The published recording-device identity algorithm from `catalog/exchange-identity.json`.
///
/// A recording Device has no natural identifier, so without one every sample carries its own
/// Device resource and a single watch is stored once per reading. This digest gives one Device
/// per participant's recorder instead.
///
/// The subject partitions the key because a wearable belongs to a person: two participants
/// wearing the same model are two devices, which is what `Device` means in R4. Firmware and
/// software are deliberately absent — they change over a recorder's life, and each Observation
/// states the versions in force when it was recorded.
public enum RecordingDeviceIdentity: Sendable {
    /// What a platform states about the recorder that produced a sample.
    public struct Recorder: Hashable, Sendable {
        public var manufacturer: String?
        public var model: String?
        public var hardwareVersion: String?

        public init(manufacturer: String? = nil, model: String? = nil, hardwareVersion: String? = nil) {
            self.manufacturer = manufacturer
            self.model = model
            self.hardwareVersion = hardwareVersion
        }
    }


    /// The identifier value that deduplicates this recorder, or `nil` when the platform states
    /// too little to identify one.
    ///
    /// Requires a manufacturer and at least one of model or hardware version: a source naming
    /// only its manufacturer would otherwise collapse every device a participant owns into one
    /// resource, so this fails closed and the caller keeps its per-sample identity.
    public static func value(subject: String, adapter: String, recorder: Recorder) -> String? {
        guard !subject.isEmpty,
              let manufacturer = recorder.manufacturer,
              !manufacturer.isEmpty else {
            return nil
        }
        let model = recorder.model ?? ""
        let hardwareVersion = recorder.hardwareVersion ?? ""
        guard !model.isEmpty || !hardwareVersion.isEmpty else {
            return nil
        }
        return compose([subject, adapter, manufacturer, model, hardwareVersion])
    }

    /// Joins components behind the scheme version. Nothing is hashed, escaped, or re-encoded.
    ///
    /// The arity is fixed at five, so an absent source field is an empty component rather than an
    /// omitted one, and the join stays unambiguous. A component carrying the separator itself has
    /// no representation here and yields `nil`, because escaping it is the conformance surface
    /// this scheme exists to remove.
    static func compose(_ parts: [String]) -> String? {
        guard parts.allSatisfy({ !$0.contains("|") }) else {
            return nil
        }
        return "v1:" + parts.joined(separator: "|")
    }
}
