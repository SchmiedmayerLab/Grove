//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The location of an EEG electrode.
public struct EEGLocation {
    /// Pg1
    public static let pg1 = EEGLocation(rawValue: "Pg1")
    /// Nz
    public static let nz = EEGLocation(rawValue: "Nz") // swiftlint:disable:this identifier_name
    /// Pg2
    public static let pg2 = EEGLocation(rawValue: "Pg2")

    /// Fp1
    public static let fp1 = EEGLocation(rawValue: "Fp1")
    /// Fpz
    public static let fpz = EEGLocation(rawValue: "Fpz")
    /// Fp2
    public static let fp2 = EEGLocation(rawValue: "Fp2")

    /// AF7
    public static let af7 = EEGLocation(rawValue: "AF7")
    /// AF3
    public static let af3 = EEGLocation(rawValue: "AF3")
    /// AFz
    public static let afz = EEGLocation(rawValue: "AFz")
    /// AF4
    public static let af4 = EEGLocation(rawValue: "AF4")
    /// AF8
    public static let af8 = EEGLocation(rawValue: "AF8")
    /// F9
    public static let f9 = EEGLocation(rawValue: "F9") // swiftlint:disable:this identifier_name
    /// F7
    public static let f7 = EEGLocation(rawValue: "F7") // swiftlint:disable:this identifier_name
    /// F5
    public static let f5 = EEGLocation(rawValue: "F5") // swiftlint:disable:this identifier_name
    /// F3
    public static let f3 = EEGLocation(rawValue: "F3") // swiftlint:disable:this identifier_name
    /// F1
    public static let f1 = EEGLocation(rawValue: "F1") // swiftlint:disable:this identifier_name
    /// Fz
    public static let fz = EEGLocation(rawValue: "Fz") // swiftlint:disable:this identifier_name
    /// F2
    public static let f2 = EEGLocation(rawValue: "F2") // swiftlint:disable:this identifier_name
    /// F4
    public static let f4 = EEGLocation(rawValue: "F4") // swiftlint:disable:this identifier_name
    /// F6
    public static let f6 = EEGLocation(rawValue: "F6") // swiftlint:disable:this identifier_name
    /// F8
    public static let f8 = EEGLocation(rawValue: "F8") // swiftlint:disable:this identifier_name
    /// F10
    public static let f10 = EEGLocation(rawValue: "F10")

    /// FT9
    public static let ft9 = EEGLocation(rawValue: "FT9")
    /// FT7
    public static let ft7 = EEGLocation(rawValue: "FT7")
    /// FC5
    public static let fc5 = EEGLocation(rawValue: "FC5")
    /// FC3
    public static let fc3 = EEGLocation(rawValue: "FC3")
    /// FC1
    public static let fc1 = EEGLocation(rawValue: "FC1")
    /// FCz
    public static let fcz = EEGLocation(rawValue: "FCz")
    /// FC2
    public static let fc2 = EEGLocation(rawValue: "FC2")
    /// FC4
    public static let fc4 = EEGLocation(rawValue: "FC4")
    /// FC6
    public static let fc6 = EEGLocation(rawValue: "FC6")
    /// FT8
    public static let ft8 = EEGLocation(rawValue: "FT8")
    /// FT10
    public static let ft10 = EEGLocation(rawValue: "FT10")
    /// A1
    public static let a1 = EEGLocation(rawValue: "A1") // swiftlint:disable:this identifier_name

    /// T9
    public static let t9 = EEGLocation(rawValue: "T9") // swiftlint:disable:this identifier_name
    /// T7
    public static let t7 = EEGLocation(rawValue: "T7") // swiftlint:disable:this identifier_name
    /// C5
    public static let c5 = EEGLocation(rawValue: "C5") // swiftlint:disable:this identifier_name
    /// C3
    public static let c3 = EEGLocation(rawValue: "C3") // swiftlint:disable:this identifier_name
    /// C1
    public static let c1 = EEGLocation(rawValue: "C1") // swiftlint:disable:this identifier_name
    /// Cz
    public static let cz = EEGLocation(rawValue: "Cz") // swiftlint:disable:this identifier_name
    /// C2
    public static let c2 = EEGLocation(rawValue: "C2") // swiftlint:disable:this identifier_name
    /// C4
    public static let c4 = EEGLocation(rawValue: "C4") // swiftlint:disable:this identifier_name
    /// C6
    public static let c6 = EEGLocation(rawValue: "C6") // swiftlint:disable:this identifier_name
    /// T8
    public static let t8 = EEGLocation(rawValue: "T8") // swiftlint:disable:this identifier_name
    /// T10
    public static let t10 = EEGLocation(rawValue: "T10")
    /// A2
    public static let a2 = EEGLocation(rawValue: "A2") // swiftlint:disable:this identifier_name

    /// T3
    public static let t3 = EEGLocation(rawValue: "T3") // swiftlint:disable:this identifier_name
    /// T4
    public static let t4 = EEGLocation(rawValue: "T4") // swiftlint:disable:this identifier_name
    /// T5
    public static let t5 = EEGLocation(rawValue: "T5") // swiftlint:disable:this identifier_name
    /// T6
    public static let t6 = EEGLocation(rawValue: "T6") // swiftlint:disable:this identifier_name

    /// TP9
    public static let tp9 = EEGLocation(rawValue: "TP9")
    /// TP7
    public static let tp7 = EEGLocation(rawValue: "TP7")
    /// CP5
    public static let cp5 = EEGLocation(rawValue: "CP5")
    /// CP3
    public static let cp3 = EEGLocation(rawValue: "CP3")
    /// CP1
    public static let cp1 = EEGLocation(rawValue: "CP1")
    /// CPz
    public static let cpz = EEGLocation(rawValue: "CPz")
    /// CP2
    public static let cp2 = EEGLocation(rawValue: "CP2")
    /// CP4
    public static let cp4 = EEGLocation(rawValue: "CP4")
    /// CP6
    public static let cp6 = EEGLocation(rawValue: "CP6")
    /// TP8
    public static let tp8 = EEGLocation(rawValue: "TP8")
    /// TP10
    public static let tp10 = EEGLocation(rawValue: "TP10")
    /// P9
    public static let p9 = EEGLocation(rawValue: "P9") // swiftlint:disable:this identifier_name

    /// P7
    public static let p7 = EEGLocation(rawValue: "P7") // swiftlint:disable:this identifier_name
    /// P5
    public static let p5 = EEGLocation(rawValue: "P5") // swiftlint:disable:this identifier_name
    /// P3
    public static let p3 = EEGLocation(rawValue: "P3") // swiftlint:disable:this identifier_name
    /// P1
    public static let p1 = EEGLocation(rawValue: "P1") // swiftlint:disable:this identifier_name
    /// Pz
    public static let pz = EEGLocation(rawValue: "Pz") // swiftlint:disable:this identifier_name
    /// P2
    public static let p2 = EEGLocation(rawValue: "P2") // swiftlint:disable:this identifier_name
    /// P4
    public static let p4 = EEGLocation(rawValue: "P4") // swiftlint:disable:this identifier_name
    /// P6
    public static let p6 = EEGLocation(rawValue: "P6") // swiftlint:disable:this identifier_name
    /// P8
    public static let p8 = EEGLocation(rawValue: "P8")
    /// P10
    public static let p10 = EEGLocation(rawValue: "P10")

    /// PO7
    public static let po7 = EEGLocation(rawValue: "PO7")
    /// PO3
    public static let po3 = EEGLocation(rawValue: "PO3")
    /// POz
    public static let poz = EEGLocation(rawValue: "POz")
    /// PO4
    public static let po4 = EEGLocation(rawValue: "PO4")
    /// PO8
    public static let po8 = EEGLocation(rawValue: "PO8")

    /// O1
    public static let o1 = EEGLocation(rawValue: "O1") // swiftlint:disable:this identifier_name
    /// Oz
    public static let oz = EEGLocation(rawValue: "Oz") // swiftlint:disable:this identifier_name
    /// O2
    public static let o2 = EEGLocation(rawValue: "O2") // swiftlint:disable:this identifier_name

    /// Iz
    public static let iz = EEGLocation(rawValue: "Iz") // swiftlint:disable:this identifier_name


    /// The string reprensetation of the eeg location.
    public let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }


    /// Create a custom EEG location.
    /// - Parameter location: The location string
    /// - Returns: The EEG location instance.
    public static func custom(_ location: String) -> EEGLocation {
        EEGLocation(rawValue: location)
    }
}

extension EEGLocation: CaseIterable {
    public static let allCases: [EEGLocation] = [
        .pg1, .nz, .pg2, .fp1, .fpz, .fp2, .af7, .af3, .afz, .af4, .af8,
        .f9, .f7, .f5, .f3, .f1, .fz, .f2, .f4, .f6, .f8, .f10, .ft9,
        .ft7, .fc5, .fc3, .fc1, .fcz, .fc2, .fc4, .fc6, .ft8, .ft10, .a1,
        .t9, .t7, .c5, .c3, .c1, .cz, .c2, .c4, .c6, .t8, .t10, .a2,
        .t3, .t4, .t5, .t6, .tp9, .tp7, .cp5, .cp3, .cp1, .cpz, .cp2,
        .cp4, .cp6, .tp8, .tp10, .p9, .p7, .p5, .p3, .p1, .pz, .p2,
        .p4, .p6, .p8, .p10, .po7, .po3, .poz, .po4, .po8, .o1, .oz,
        .o2, .iz
    ]
}

extension EEGLocation: Identifiable {
    public var id: String {
        rawValue
    }
}

extension EEGLocation: Hashable, Sendable {}


extension EEGLocation: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        let rawValue = try container.decode(String.self)
        self.init(rawValue: rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
