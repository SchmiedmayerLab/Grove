//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SnapshotTesting)
import SnapshotTesting
#endif
@testable import SpeziViews
import SwiftUI
import Testing

extension SnapshotTests {
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    struct Options: OptionSet, PickerValue {
        static let allCases: [Options] = [.option1, .option2]
        static let option1 = Options(rawValue: 1 << 0)
        static let option2 = Options(rawValue: 1 << 1)
        
        var rawValue: UInt8
        var localizedStringResource: LocalizedStringResource {
            "Option \(rawValue)"
        }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    enum Version: PickerValue {
        case versionA
        case versionB

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .versionA:
                "A"
            case .versionB:
                "B"
            }
        }
    }

    @Test("Option Set Picker")
    func optionSetPicker() {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *) else {
            return
        }

        let picker0 = List {
            OptionSetPicker("Clean", selection: .constant(Options.option1))
        }
        let picker1 = List {
            OptionSetPicker("Code", selection: .constant(Options.option1.union(.option2)), style: .inline, allowEmptySelection: true)
        }

#if os(iOS)
        assertSnapshot(of: picker0, as: .image(layout: .device(config: .iPhone13Pro)), named: "option-picker")
        assertSnapshot(of: picker1, as: .image(layout: .device(config: .iPhone13Pro)), named: "option-picker-inline")
#endif
    }

    @Test("Case Iterable Picker")
    func caseIterablePicker() {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *) else {
            return
        }

        let picker = List {
            CaseIterablePicker("Clean Code", selection: .constant(Version.versionA))
        }

#if os(iOS)
        assertSnapshot(of: picker, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-regular")
#endif
    }
}
