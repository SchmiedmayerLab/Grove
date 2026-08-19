//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Omron Model.
public struct OmronModel {
    /// The raw model number.
    public let rawValue: String

    /// Initialize from raw value.
    /// - Parameter rawValue: The raw model number string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}


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


extension OmronModel: RawRepresentable {}


extension OmronModel: Hashable, Sendable {}


extension OmronModel: Codable {}
