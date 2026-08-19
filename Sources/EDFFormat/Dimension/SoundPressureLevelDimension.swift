//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A SPL dimension.
public enum SoundPressureLevelDimension: String {
    case dB // swiftlint:disable:this identifier_name
    case dBA
    case dBB
    case dBC
    case DBL
}


extension SoundPressureLevelDimension: Hashable, Sendable {}
