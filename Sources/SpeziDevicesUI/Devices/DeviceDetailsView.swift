//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth
@_spi(Internal)
@_spi(TestingSupport)
import SpeziDevices
import SpeziViews
import SwiftUI


/// Show the device details of a paired device.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public struct DeviceDetailsView: View {
    private enum Event {
        case forgetDevice
    }

    private let deviceInfo: PairedDeviceInfo

    @Environment(\.dismiss)
    private var dismiss
    @Environment(PairedDevices.self)
    private var pairedDevices

    @State private var viewState: ViewState = .idle
    @State private var presentForgetConfirmation = false
    @State private var events: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation) = AsyncStream.makeStream()

    private var image: Image {
        deviceInfo.icon?.image ?? Image(systemName: "sensor") // swiftlint:disable:this accessibility_label_for_image
    }

    private var shouldShowModelSeparately: Bool {
        deviceInfo.managedByAccessorySetupKit && deviceInfo.model != nil && deviceInfo.model != deviceInfo.name
    }

    public var body: some View {
        List {
            deviceInformation
            Section {
                AsyncButton(state: $viewState) {
                    presentForgetConfirmation = true
                } label: {
                    Text("Forget This Device", bundle: .module)
                }
                .confirmationDialog(
                    Text("Do you really want to forget this device?", bundle: .module),
                    isPresented: $presentForgetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive, action: scheduleForgetDevice) {
                        Text("Forget Device", bundle: .module)
                    }
                    Button(role: .cancel) {} label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            } footer: {
                if pairedDevices.isConnected(device: deviceInfo.id) {
                    Text("Synchronizing ...", bundle: .module)
                } else {
                    Text(
                        "This device was last seen \(Text.deviceLastSeen(date: deviceInfo.lastSeen)).",
                        bundle: .module
                    )
                }
            }
        }
            .navigationTitle(Text("Device Details", bundle: .module))
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .viewStateAlert(state: $viewState)
            .task {
                for await event in events.stream {
                    switch event {
                    case .forgetDevice:
                        await self.handleForgetDevice()
                    }
                }

                self.events = AsyncStream.makeStream() // make sure onAppear works repeatedly.
            }
            .toolbar {
                if pairedDevices.isConnected(device: deviceInfo.id) {
                    ToolbarItem(placement: .primaryAction) {
                        ProgressView()
                    }
                }
            }
    }
    
    @ViewBuilder private var deviceInformation: some View {
        Section {
            imageHeader
        }

        if #available(iOS 18, visionOS 2.0, *), deviceInfo.managedByAccessorySetupKit {
            Section("Name") {
                AccessoryRenameButton(deviceInfo: deviceInfo)
            }
        } else {
            Section {
                DeviceNameRow(deviceInfo: deviceInfo)
                DeviceModelRow(deviceInfo: deviceInfo)
            }
        }

        if deviceInfo.lastBatteryPercentage != nil || shouldShowModelSeparately {
            Section("About") {
                DeviceBatteryInfoRow(deviceInfo: deviceInfo)
                DeviceModelRow(deviceInfo: deviceInfo)
            }
        }
    }

    @ViewBuilder private var imageHeader: some View {
        VStack(alignment: .center) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.accentColor) // set accent color if one uses sf symbols
                .symbolRenderingMode(.hierarchical) // set symbol rendering mode if one uses sf symbols
                .frame(maxWidth: 180, maxHeight: 120)
                .accessibilityHidden(true)
        }
            .frame(maxWidth: .infinity)
    }


    /// Create a new device details view.
    /// - Parameter deviceInfo: The device info of the paired device.
    public init(_ deviceInfo: PairedDeviceInfo) {
        self.deviceInfo = deviceInfo
    }

    private func scheduleForgetDevice() {
        events.continuation.yield(.forgetDevice)
    }

    private func handleForgetDevice() async {
        guard case .idle = viewState else {
            return
        }

        viewState = .processing

        do {
            #if !targetEnvironment(macCatalyst)
            let managedByAccessorySetupKit = if #available(iOS 18, visionOS 2, *), AccessorySetupKit.supportedProtocols.contains(.bluetooth) {
                true
            } else {
                false
            }
            #else
            let managedByAccessorySetupKit = false
            #endif
            
            try await pairedDevices.forgetDevice(id: deviceInfo.id)
            if !managedByAccessorySetupKit {
                ForgetDeviceTip.hasRemovedPairedDevice = true
            }
            dismiss()
            viewState = .idle
        } catch {
            viewState = .error(AnyLocalizedError(
                error: error,
                defaultErrorDescription: .init("Failed to forget device", bundle: .atURL(from: .module))
            ))
        }
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    NavigationStack {
        DeviceDetailsView(PairedDeviceInfo(
            id: UUID(),
            deviceType: MockDevice.deviceTypeIdentifier,
            name: "Blood Pressure Monitor",
            model: "BP5250",
            lastSeen: .now.addingTimeInterval(-120),
            batteryPercentage: 100
        ))
    }
        .previewWith {
            PairedDevices()
        }
}

@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    NavigationStack {
        DeviceDetailsView(PairedDeviceInfo(
            id: UUID(),
            deviceType: MockDevice.deviceTypeIdentifier,
            name: "Weight Scale",
            model: "SC-150",
            lastSeen: .now.addingTimeInterval(-60 * 60 * 24),
            batteryPercentage: 85
        ))
    }
        .previewWith {
            PairedDevices()
        }
}
#endif
