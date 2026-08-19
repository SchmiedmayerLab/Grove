//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A temperature dimension.
public enum TemperatureDimension: String {
    case kelvin = "K"
    case celsius = "degC"
    case fahrenheit = "degF"
}


extension TemperatureDimension: Hashable, Sendable {}
