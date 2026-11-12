//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Omron Model.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct OmronModel {
    /// The raw model number.
    public let rawValue: String

    /// Initialize from raw value.
    /// - Parameter rawValue: The raw model number string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronModel {
    /// The Omron SC150 weight scale.
    public static let sc150 = OmronModel(rawValue: "SC-150")
    /// The Omron BP5250 blood pressure monitor.
    public static let bp5250 = OmronModel(rawValue: "BP5250")
    /// The Omron EVOLV blood pressure monitor.
    public static let evolv = OmronModel(rawValue: "EVOLV")
    /// The Omron BP7000 blood pressure monitor.
    public static let bp7000 = OmronModel(rawValue: "BP7000")
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronModel: RawRepresentable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronModel: Hashable, Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronModel: Codable {}
