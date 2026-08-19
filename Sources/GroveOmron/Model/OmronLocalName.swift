//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import RegexBuilder


/// The local name of a Omron device.
///
/// The local name is part of the advertisement sent by a Omron device.
/// It includes additional information about the device.
///
/// A local name typically starts with the `BLESmart_` prefix, followed by 4 bytes of model identifier and 6 bytes of the Bluetooth Mac Address.
/// However, if the `s` is lowercase in `BLEsmart_`, the device signals that it is advertising in pairing mode.
public struct OmronLocalName {
    /// The pairing mode derived from the local name.
    public enum PairingMode {
        /// The device is in transfer mode.
        case transferMode
        /// The device is in pairing mode.
        case pairingMode

        var prefix: String {
            switch self {
            case .transferMode:
                "BLESmart_"
            case .pairingMode:
                "BLEsmart_"
            }
        }

        init?(fromPrefix prefix: String) {
            switch prefix {
            case "BLESmart_":
                self = .transferMode
            case "BLEsmart_": // yeah, that's funny
                self = .pairingMode
            default:
                return nil
            }
        }
    }

    /// The model identifier derived from the local name.
    public struct ModelIdentifier: RawRepresentable {
        public var rawValue: String

        public init?(rawValue: String) {
            guard rawValue.count == 8 else {
                return nil
            }
            self.rawValue = rawValue
        }
    }

    /// The Bluetooth Mac address as advertised within the local name.
    public struct MacAddress: RawRepresentable {
        public var rawValue: String

        public init?(rawValue: String) {
            guard rawValue.count == 12 else {
                return nil
            }
            self.rawValue = rawValue
        }
    }

    /// The pairing mode derived from the local name.
    public let pairingMode: PairingMode
    /// The device identifier part of the local name string.
    public let model: ModelIdentifier
    /// The mac address part of the local name.
    public let macAddress: MacAddress

    /// The local name raw value.
    public var rawValue: String {
        pairingMode.prefix + model.rawValue + macAddress.rawValue
    }


    /// Initialize the local name from the raw value string.
    /// - Parameter rawValue: The local name raw value.
    @available(iOS 18, macOS 15, watchOS 11, *)
    public init?(rawValue: String) {
        let pattern = Regex {
            TryCapture {
                ChoiceOf {
                    "BLESmart_"
                    "BLEsmart_"
                }
            } transform: { output in
                PairingMode(fromPrefix: String(output))
            }
            TryCapture {
                Repeat(.hexDigit, count: 2 * 4)
            } transform: { output in
                ModelIdentifier(rawValue: String(output))
            }
            TryCapture {
                Repeat(.hexDigit, count: 2 * 6)
            } transform: { output in
                MacAddress(rawValue: String(output))
            }
        }
        guard let match = rawValue.wholeMatch(of: pattern) else {
            return nil
        }

        let (_, pairingMode, model, macAddress) = match.output
        self.pairingMode = pairingMode
        self.model = model
        self.macAddress = macAddress
    }
}


extension OmronLocalName.PairingMode: Sendable, Hashable {}


extension OmronLocalName.ModelIdentifier: Sendable, Hashable {}


extension OmronLocalName.MacAddress: Sendable, Hashable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronLocalName: RawRepresentable, Sendable, Hashable {}
