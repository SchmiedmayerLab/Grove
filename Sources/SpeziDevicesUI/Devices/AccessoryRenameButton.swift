//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(AccessorySetupKit) && !os(macOS)
import AccessorySetupKit
#endif
import OSLog
@_spi(Internal)
import SpeziDevices
import SpeziViews
import SwiftUI


@available(iOS 18, *)
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct AccessoryRenameButton: View {
    private struct MissingAccessory: LocalizedError {
        var errorDescription: String? {
            "Unsupported" // this is a developer error. therefore we do not really localize here
        }

        var failureReason: String? {
            "This accessory seems to not be managed by the AccessorySetupKit!"
        }

        init() {}
    }

    private let deviceInfo: PairedDeviceInfo

    @Environment(PairedDevices.self)
    private var pairedDevices

    @State private var viewState: ViewState = .idle

    @State private var actionTask: Task<Void, Never>?

    var body: some View {
        Button(action: renameAccessory) {
            LabeledContent {
                Text("Change")
                    .foregroundStyle(Color.accentColor)
            } label: {
                Text(deviceInfo.name)
                    .foregroundStyle(Color.primary)
            }
        }
            .disabled(viewState != .idle)
            .viewStateAlert(state: $viewState)
            .onDisappear {
                actionTask?.cancel()
            }
    }


    init(deviceInfo: PairedDeviceInfo) {
        self.deviceInfo = deviceInfo
    }

    private func renameAccessory() {
        // we don't set the view state currently to processing, as some never iOS 18 versions have `renameAccessory`
        // never actually return (leak in AccessorySetupKit).

        actionTask?.cancel()
        actionTask = Task {
            do {
                try await _renameAccessory()
            } catch {
                viewState = .error(AnyLocalizedError(
                    error: error,
                    defaultErrorDescription: "Failed to rename accessory."
                ))
            }
        }
    }

    private func _renameAccessory() async throws {
#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
        guard let accessory = deviceInfo.accessory else {
            throw MissingAccessory()
        }

        try await pairedDevices.renameAccessory(for: accessory)
#endif
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    let deviceInfo = PairedDeviceInfo(id: .init(), deviceType: "MockDevice", name: "BP", model: "BP5250")
    List {
        DeviceModelRow(deviceInfo: deviceInfo)
    }
        .previewWith {
            PairedDevices()
        }
}
#endif
