//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import GroveDevices
import GroveValidation
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct NameEditView: View {
    private let deviceInfo: PairedDeviceInfo
    private let save: (String) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var name: String

    @ValidationState private var validation

    var body: some View {
        List {
            VerifiableTextField("enter device name", text: $name)
                .validate(input: name, rules: [.nonEmpty, .deviceNameMaxLength])
                .receiveValidation(in: $validation)
#if !os(macOS)
                .autocapitalization(.words)
#endif
        }
            .navigationTitle(Text("Name", bundle: .module))
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                Button {
                    save(name)
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                    .disabled(deviceInfo.name == name || !validation.allInputValid)
            }
    }


    init(_ deviceInfo: PairedDeviceInfo, save: @escaping (String) -> Void) {
        self.deviceInfo = deviceInfo
        self.save = save
        self._name = State(wrappedValue: deviceInfo.name)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ValidationRule {
    static var deviceNameMaxLength: ValidationRule {
        ValidationRule(rule: { input in
            input.count <= 50
        }, message: .init("The device name cannot be longer than 50 characters.", bundle: .atURL(from: .module)))
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    NavigationStack {
        NameEditView(PairedDeviceInfo(
            id: UUID(),
            deviceType: MockDevice.deviceTypeIdentifier,
            name: "Blood Pressure Monitor",
            model: "BP5250",
            batteryPercentage: 100
        )) { name in
            print("New Name is \(name)")
        }
    }
}
#endif
