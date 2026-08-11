//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Signal label according to EDF+ specification.
///
/// For more information refer to [Text and Polarity Rules](https://www.edfplus.info/specs/edftexts.html).
public enum SignalType: String {
    case distance = "Dist"
    case area = "Area"
    case volume = "Volume"
    case duration = "Dur"
    case velocity = "Velocity"
    case mass = "Mass"
    case angle = "Angle"
    case percentage = "%"
    case money = "Value"
    case eeg = "EEG"
    case ecg = "ECG"
    case eog = "EOG"
    case erg = "ERG"
    case emg = "EMG"
    case meg = "MEG"
    case mcg = "MCG"
    case evokedPotential = "EP"
    case temperature = "Temp"
    case respiration = "Resp"
    case oxygenSaturation = "SaO2"
    case light = "Light"
    case sound = "Sound"
    case events = "Event"
}


extension SignalType: Hashable, Sendable {}
