//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The dimension of an angle.
public enum AngleDimension: String {
    case degree = "deg"
    case radian = "rad"
}


extension AngleDimension: Hashable, Sendable {}
