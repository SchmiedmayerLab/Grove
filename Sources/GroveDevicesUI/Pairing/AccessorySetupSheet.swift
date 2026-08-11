//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveBluetooth
@_spi(TestingSupport)
public import GroveDevices
import GroveViews
import OSLog
public import SwiftUI


/// Accessory Setup view displayed in a sheet.
@available(iOS 18, macOS 15, watchOS 11, *)
@available(macOS, unavailable)
public struct AccessorySetupSheet<Collection: RandomAccessCollection, PairingHint: View>: View where Collection.Element == any PairableDevice {
    private static var logger: Logger {
        Logger(subsystem: "org.grovealliance.devices", category: "AccessorySetupSheet")
    }

    private let devices: Collection
    private let appName: String
    private let pairingHint: PairingHint

    @Environment(Bluetooth.self)
    private var bluetooth
    @Environment(PairedDevices.self)
    private var pairedDevices

    @State private var pairingState: PairingViewState = .discovery

    public var body: some View {
        NavigationStack {
            VStack {
                if case let .error(error) = pairingState {
                    PairingFailureView(error)
                } else if case let .paired(device) = pairingState {
                    PairedDeviceView(device, appName: appName)
                } else if !devices.isEmpty {
                    PairDeviceView(devices: devices, appName: appName, state: $pairingState) { device in
                        do {
                            try await pairedDevices.pair(with: device)
                        } catch {
                            Self.logger.error("Failed to pair device \(device.id), \(device.name ?? "unnamed"): \(error)")
                            throw error
                        }
                    }
                } else {
                    DiscoveryView {
                        pairingHint
                    }
                }
            }
                .toolbar {
                    DismissButton()
                }
        }
            .scanNearbyDevices(with: bluetooth)
            .presentationDetents([.medium])
            .presentationCornerRadius(25)
            .interactiveDismissDisabled()
            .accessibilityIdentifier("AccessorySetupSheet")
    }

    /// Create a new Accessory Setup sheet.
    /// - Parameters:
    ///   - devices: The collection of nearby devices which are available for pairing.
    ///   - appName: The name of the application to show in the pairing UI.
    ///   - pairingHint: The pairing hint to display in the Discovery view.
    public init(_ devices: Collection, appName: String, @ViewBuilder pairingHint: () -> PairingHint = { EmptyView() }) {
        self.devices = devices
        self.appName = appName
        self.pairingHint = pairingHint()
    }

    /// Create a new Accessory Setup sheet.
    /// - Parameters:
    ///   - devices: The collection of nearby devices which are available for pairing.
    ///   - appName: The name of the application to show in the pairing UI.
    ///   - pairingHint: The pairing hint to display in the Discovery view.
    public init(_ devices: Collection, appName: String, pairingHint: Text) where PairingHint == Text {
        self.init(devices, appName: appName) {
            pairingHint
        }
    }

    /// Create a new Accessory Setup sheet.
    /// - Parameters:
    ///   - devices: The collection of nearby devices which are available for pairing.
    ///   - appName: The name of the application to show in the pairing UI.
    ///   - pairingHint: The pairing hint to display in the Discovery view.
    public init(_ devices: Collection, appName: String, pairingHint: LocalizedStringResource) where PairingHint == Text {
        self.init(devices, appName: appName, pairingHint: Text(pairingHint))
    }
}


#if DEBUG && !os(macOS)
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) {
            AccessorySetupSheet([MockDevice.createMockDevice()], appName: "Example") {
                Text(verbatim: "Make sure to enable pairing mode on the device.")
            }
        }
        .previewWith {
            Bluetooth {}
            PairedDevices()
        }
}


@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) {
            let devices: [any PairableDevice] = [
                MockDevice.createMockDevice(name: "Device 1"),
                MockDevice.createMockDevice(name: "Device 2")
            ]
            AccessorySetupSheet(devices, appName: "Example") {
                Text(verbatim: "Make sure to enable pairing mode on the device.")
            }
        }
        .previewWith {
            Bluetooth {}
            PairedDevices()
        }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) {
            AccessorySetupSheet([], appName: "Example") {
                Text(verbatim: "Make sure to enable pairing mode on the device.")
            }
        }
        .previewWith {
            Bluetooth {}
            PairedDevices()
        }
}
#endif
