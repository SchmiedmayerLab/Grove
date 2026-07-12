//
// This source file is part of the Stanford Spezi open-project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import SpeziDevices
import SpeziViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
@available(macOS, unavailable)
struct PairDeviceView<Collection: RandomAccessCollection>: View where Collection.Element == any PairableDevice {
    private let devices: Collection
    private let appName: String
    private let pairClosure: (any PairableDevice) async throws -> Void

    @Environment(\.dismiss)
    private var dismiss

    @Binding private var pairingState: PairingViewState
    @AccessibilityFocusState private var isHeaderFocused: Bool

    @State private var selectedDeviceId: UUID?
    @State private var selectedDevice: (any PairableDevice)?


    private var forcedUnwrappedDeviceId: Binding<UUID> {
        Binding {
            guard let selectedDeviceId = selectedDeviceId ?? devices.first?.id else {
                preconditionFailure("Entered code path where selectedMeasurement was not set.")
            }
            return selectedDeviceId
        } set: { newValue in
            selectedDeviceId = newValue
        }
    }

    private var selectedDeviceName: String {
        selectedDevice.map { "\"\($0.label)\"" } ?? "the accessory"
    }

    var body: some View {
        PaneContent(
            title: .init("Pair Accessory", bundle: .module),
            subtitle: .init("Do you want to pair \(selectedDeviceName) with the \(appName) app?", bundle: .module)
        ) {
            if devices.count > 1 {
                TabView(selection: forcedUnwrappedDeviceId) {
                    ForEach(devices, id: \.id) { device in
                        VStack {
                            AccessoryImageView(device)
                            Spacer()
                                .frame(minHeight: 30, idealHeight: 45, maxHeight: 60)
                                .fixedSize()
                        }
                            .tag(device.id)
                    }
                }
                    .onChange(of: selectedDeviceId, initial: true) {
                        if selectedDeviceId == nil {
                            self.selectedDeviceId = devices.first?.id
                        }
                        selectedDevice = devices.first(where: { $0.id == selectedDeviceId })
                    }
#if !os(macOS)
                    .tabViewStyle(.page)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
#endif
            } else if let device = devices.first {
                AccessoryImageView(device)
                    .onAppear {
                        selectedDevice = device
                    }
            }
        } action: {
            AsyncButton {
                guard let selectedDevice else {
                    return
                }

                guard case .discovery = pairingState else {
                    return
                }

                pairingState = .pairing

                do {
                    try await pairClosure(selectedDevice)
                    pairingState = .paired(selectedDevice)
                } catch {
                    pairingState = .error(AnyLocalizedError(error: error))
                }
            } label: {
                Text("Pair", bundle: .module)
                    .frame(maxWidth: .infinity, maxHeight: 35)
            }
                .buttonStyle(.borderedProminent)
                .padding([.leading, .trailing], 36)
        }
    }


    init(devices: Collection, appName: String, state: Binding<PairingViewState>, pair: @escaping (any PairableDevice) async throws -> Void) {
        self.devices = devices
        self.appName = appName
        self._pairingState = state
        self.pairClosure = pair
    }
}


#if DEBUG && !os(macOS)
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    SheetPreview {
        PairDeviceView(devices: [MockDevice.createMockDevice()], appName: "Example", state: .constant(.discovery)) { _ in
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    SheetPreview {
        let device: [any PairableDevice] = [
            MockDevice.createMockDevice(name: "Device 1"),
            MockDevice.createMockDevice(name: "Device 2")
        ]
        PairDeviceView(devices: device, appName: "Example", state: .constant(.discovery)) { device in
            print("Pairing \(device.label)")
        }
    }
}
#endif
