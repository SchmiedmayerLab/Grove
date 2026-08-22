//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
public import Foundation


/// The published recording-device identity algorithm from `catalog/exchange-identity.json`.
///
/// A recording Device has no natural identifier: a platform that exposes a per-unit serial is the
/// exception, not the rule. Without one, every sample yields its own Device resource, so a single
/// watch is stored thousands of times. These digests give a deployment one Device per recorder
/// configuration instead, deduplicated by a stable business identifier.
///
/// The firmware and software versions participate in the key on purpose. The Device resource
/// represents them, so a configuration change mints a new Device rather than mutating a shared
/// one. Every emitted Device therefore stays immutable, and a backfill that converts an old
/// sample after a newer one writes byte-identical content instead of silently downgrading the
/// firmware a consumer already stored.
public enum GroveFHIRRecordingDeviceIdentity: Sendable {
    /// Which fact the key rests on, recorded in the digest so one kind can never collide
    /// with another.
    public enum KeyKind: String, Hashable, Sendable {
        /// The product configuration. This identifies a model within one deployment scope, not an
        /// individual unit: two identical units in one scope deduplicate into one Device.
        case modelClass = "model-class"
        /// An opaque installation-local platform identifier the deployment has authorized.
        case localIdentifier = "local-identifier"
    }

    /// What a platform states about the recorder that produced a sample.
    public struct Recorder: Hashable, Sendable {
        public var manufacturer: String?
        public var model: String?
        public var hardwareVersion: String?
        public var firmwareVersion: String?
        public var softwareVersion: String?
        /// An opaque platform identifier for the unit, where one exists.
        public var localIdentifier: String?

        public init(
            manufacturer: String? = nil,
            model: String? = nil,
            hardwareVersion: String? = nil,
            firmwareVersion: String? = nil,
            softwareVersion: String? = nil,
            localIdentifier: String? = nil
        ) {
            self.manufacturer = manufacturer
            self.model = model
            self.hardwareVersion = hardwareVersion
            self.firmwareVersion = firmwareVersion
            self.softwareVersion = softwareVersion
            self.localIdentifier = localIdentifier
        }
    }

    private static let domain = "grove-recording-device-id-v1"

    /// The identifier value that deduplicates this recorder, or `nil` when the platform states
    /// too little to identify one.
    ///
    /// A local identifier names the unit, so it takes precedence over the product configuration.
    /// A configuration key requires a manufacturer and at least one of model or hardware version:
    /// a source naming only its manufacturer would otherwise collapse every device a participant
    /// owns into one resource, so this fails closed and the caller keeps its per-sample identity.
    public static func value(scope: String, adapter: String, recorder: Recorder) -> String? {
        guard !scope.isEmpty else {
            return nil
        }
        let firmware = recorder.firmwareVersion ?? ""
        let software = recorder.softwareVersion ?? ""
        if let localIdentifier = recorder.localIdentifier, !localIdentifier.isEmpty {
            return digest([
                domain, scope, adapter, KeyKind.localIdentifier.rawValue,
                localIdentifier, firmware, software
            ])
        }
        guard let manufacturer = recorder.manufacturer, !manufacturer.isEmpty else {
            return nil
        }
        let model = recorder.model ?? ""
        let hardwareVersion = recorder.hardwareVersion ?? ""
        guard !model.isEmpty || !hardwareVersion.isEmpty else {
            return nil
        }
        return digest([
            domain, scope, adapter, KeyKind.modelClass.rawValue,
            manufacturer, model, hardwareVersion, firmware, software
        ])
    }

    /// RFC 8785/JCS serialization of an array of strings, matching the published lexical rules.
    public static func canonicalName(_ parts: [String]) -> String {
        "[" + parts.map { GroveFHIRExchangeIdentity.quotedJCSString($0) }.joined(separator: ",") + "]"
    }

    private static func digest(_ parts: [String]) -> String {
        let hashed = SHA256.hash(data: Data(canonicalName(parts).utf8))
        return "v1:" + hashed.map { String(format: "%02x", $0) }.joined()
    }
}
