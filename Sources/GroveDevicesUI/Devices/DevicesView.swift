//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveBluetooth
import GroveDevices
public import SwiftUI


/// Devices view showing grid of paired devices and provides functionality to pair new devices.
///
/// - Note: Make sure to place this view into an `NavigationStack`.
@available(iOS 18, macOS 15, watchOS 11, *)
@available(macOS, unavailable)
public struct DevicesView<PairingHint: View>: View {
    private let appName: String
    private let pairingHint: PairingHint

    @Environment(Bluetooth.self)
    private var bluetooth
    @Environment(PairedDevices.self)
    private var pairedDevices

    public var body: some View {
        @Bindable var pairedDevices = pairedDevices

        DevicesGrid(devices: pairedDevices.pairedDevices) {
            pairedDevices.showAccessoryDiscovery()
        }
            .navigationTitle(Text("Devices", bundle: .module))
            // automatically search if no devices are paired
            .scanNearbyDevices(enabled: pairedDevices.isScanningForNearbyDevices, with: bluetooth)
            .sheet(isPresented: $pairedDevices.shouldPresentDevicePairing) {
                AccessorySetupSheet(pairedDevices.discoveredDevices, appName: appName) {
                    pairingHint
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // indicate that we are scanning in the background
                    if pairedDevices.isScanningForNearbyDevices && !pairedDevices.shouldPresentDevicePairing {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Device", systemImage: "plus") {
                        pairedDevices.showAccessoryDiscovery()
                    }
                }
            }
    }

    /// Create a new devices tab
    /// - Parameters:
    ///   - appName: The name of the application to show in the pairing UI.
    ///   - pairingHint: The pairing hint to display in the Discovery view.
    public init(appName: String, @ViewBuilder pairingHint: () -> PairingHint = { EmptyView() }) {
        self.appName = appName
        self.pairingHint = pairingHint()
    }

    /// Create a new devices tab
    /// - Parameters:
    ///   - appName: The name of the application to show in the pairing UI.
    ///   - pairingHint: The pairing hint to display in the Discovery view.
    public init(appName: String, pairingHint: Text) where PairingHint == Text {
        self.init(appName: appName) {
            pairingHint
        }
    }

    /// Create a new devices tab
    /// - Parameters:
    ///   - appName: The name of the application to show in the pairing UI.
    ///   - pairingHint: The pairing hint to display in the Discovery view.
    public init(appName: String, pairingHint: LocalizedStringResource) where PairingHint == Text {
        self.init(appName: appName, pairingHint: Text(pairingHint))
    }
}


#if DEBUG && !os(macOS)
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    NavigationStack {
        DevicesView(appName: "Example")
            .previewWith {
                Bluetooth {}
                PairedDevices()
            }
    }
}
#endif
