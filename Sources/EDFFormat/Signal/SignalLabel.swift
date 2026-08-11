//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The label of a signal.
///
/// For more information on structured signal descriptions refer to the
/// [EDF List of signals](https://www.edfplus.info/specs/edftexts.html#signals).
public struct SignalLabel {
    /// The signal type.
    public let type: SignalType
    /// The location where the signal is measured.
    public let location: String?
    /// The dimension in which the signal is measured (e.g., "uV").
    public let dimension: String

    var rawValue: String {
        type.rawValue
            + (location.map { " " + $0 } ?? "")
    }


    fileprivate init(type: SignalType, location: String? = nil, prefix: DimensionPrefix = .none, dimension: String? = nil) {
        self.type = type
        self.location = location
        self.dimension = dimension.map { prefix.rawValue + $0 } ?? ""
    }
}


extension SignalLabel: Hashable, Sendable {}


extension SignalLabel {
    /// A length or distance measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func distance(location: String? = nil, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .distance, location: location, prefix: prefix, dimension: "m")
    }

    /// A area measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func area(location: String? = nil, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .area, location: location, prefix: prefix, dimension: "m^2")
    }

    /// A volume measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func volume(location: String? = nil, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .volume, location: location, prefix: prefix, dimension: "m^3")
    }

    /// A duration measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func duration(location: String? = nil, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .duration, location: location, prefix: prefix, dimension: "s")
    }

    /// A velocity measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func velocity(location: String? = nil, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .velocity, location: location, prefix: prefix, dimension: "m/s")
    }

    /// A mass measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func mass(location: String? = nil, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .mass, location: location, prefix: prefix, dimension: "g")
    }

    /// An angle measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    ///   - dimension: The angle dimension
    /// - Returns: The signal label.
    public static func angle(location: String? = nil, prefix: DimensionPrefix = .none, dimension: AngleDimension) -> SignalLabel {
        SignalLabel(type: .angle, location: location, prefix: prefix, dimension: dimension.rawValue)
    }

    /// A percentage measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func percentage(location: String? = nil) -> SignalLabel {
        SignalLabel(type: .mass, location: location, dimension: "%")
    }

    /// A money measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - dimension: The money dimension (e.g., "EUR").
    ///     Refer to [EDF Currencies](https://www.edfplus.info/specs/edftexts.html#prefixes_electrodenames) for more information.
    /// - Returns: The signal label.
    public static func money(location: String? = nil, dimension: String) -> SignalLabel {
        SignalLabel(type: .money, location: location, dimension: dimension)
    }
}

extension SignalLabel {
    /// An Electroencephalogram measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func eeg(location: EEGLocation, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .eeg, location: location.rawValue, prefix: prefix, dimension: "V")
    }

    /// An Electrocardiogram measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func ecg(location: String, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .ecg, location: location, prefix: prefix, dimension: "V")
    }

    /// An Electroöculogram measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func eog(location: String, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .eog, location: location, prefix: prefix, dimension: "V")
    }

    /// An Electroretinogram measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func erg(location: String, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .erg, location: location, prefix: prefix, dimension: "V")
    }

    /// An Electromyogram measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - prefix: The dimension prefix.
    /// - Returns: The signal label.
    public static func emg(location: String, prefix: DimensionPrefix = .none) -> SignalLabel {
        SignalLabel(type: .emg, location: location, prefix: prefix, dimension: "V")
    }

    /// An Magneto Encephalogram measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func meg(location: String) -> SignalLabel {
        SignalLabel(type: .meg, location: location)
    }

    /// An Magneto Cardiogram measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func mcg(location: String) -> SignalLabel {
        SignalLabel(type: .mcg, location: location)
    }

    /// An Evoked Potential measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func evokedPotential(location: String) -> SignalLabel {
        SignalLabel(type: .evokedPotential, location: location)
    }
}


extension SignalLabel {
    /// A temperature measurement.
    ///
    /// - Parameters:
    ///   - location: The location of the measurement.
    ///   - dimension: The dimension of the measurement.
    /// - Returns: The signal label.
    public static func temperature(location: String? = nil, dimension: TemperatureDimension) -> SignalLabel {
        SignalLabel(type: .temperature, location: location, dimension: dimension.rawValue)
    }

    /// A respiration measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func respiration(location: String? = nil) -> SignalLabel {
        SignalLabel(type: .respiration, location: location)
    }

    /// An oxygen saturation measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func oxygenSaturation(location: String? = nil) -> SignalLabel {
        SignalLabel(type: .oxygenSaturation, location: location, dimension: "%")
    }

    /// A light measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func light(location: String? = nil) -> SignalLabel {
        SignalLabel(type: .light, location: location)
    }

    /// A sound measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func sound(location: String? = nil) -> SignalLabel {
        SignalLabel(type: .sound, location: location)
    }

    /// A sound pressure level measurement.
    ///
    /// - Parameter dimension: The dimension of the measurement.
    /// - Returns: The signal label.
    public static func soundPressureLevel(dimension: SoundPressureLevelDimension) -> SignalLabel {
        SignalLabel(type: .sound, location: "SPL", dimension: dimension.rawValue)
    }

    /// An events measurement.
    ///
    /// - Parameter location: The location of the measurement.
    /// - Returns: The signal label.
    public static func events(location: String? = nil) -> SignalLabel {
        SignalLabel(type: .events, location: location)
    }
}


extension SignalLabel {
    /// Create a custom signal label.
    /// 
    /// - Parameters:
    ///   - type: The signal type.
    ///   - location: The signal location.
    ///   - prefix: The dimension prefix.
    ///   - dimension: The signal dimension.
    /// - Returns: The signal label.
    public static func custom(type: SignalType, location: String? = nil, prefix: DimensionPrefix = .none, dimension: String? = nil) -> SignalLabel {
        SignalLabel(type: type, location: location, prefix: prefix, dimension: dimension)
    }
}
