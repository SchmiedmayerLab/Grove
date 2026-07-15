//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
public import SpeziDevices
public import SwiftUI


/// A tile showing a paired device.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct DeviceTile: View {
    private let deviceInfo: PairedDeviceInfo

    @Environment(PairedDevices.self)
    private var pairedDevices

    private var image: Image {
        deviceInfo.icon?.image ?? Image(systemName: "sensor") // swiftlint:disable:this accessibility_label_for_image
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.accentColor) // set accent color if one uses sf symbols
                    .symbolRenderingMode(.hierarchical) // set symbol rendering mode if one uses sf symbols
                    .accessibilityHidden(true)
                    .frame(minWidth: 0, maxWidth: 100, minHeight: 0, maxHeight: 120, alignment: .topLeading)
                Spacer()

                if pairedDevices.isConnected(device: deviceInfo.id) {
                    ProgressView()
                }
            }
                .accessibilityHidden(true)
            Spacer()
            HStack {
                Text(deviceInfo.name)
                    .foregroundStyle(.primary)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if let percentage = deviceInfo.lastBatteryPercentage {
                    BatteryIcon(percentage: Int(percentage))
                        .labelStyle(.iconOnly)
                }
            }
        }
            .padding(16)
            .background {
                RoundedRectangle(cornerSize: CGSize(width: 25, height: 25))
#if canImport(UIKit)
                    .foregroundStyle(Color(uiColor: .secondarySystemGroupedBackground))
#endif
            }
            .aspectRatio(1.0, contentMode: .fit) // explicit aspect ratio to ensure tile is always square
            .accessibilityElement(children: .combine)
            .accessibilityRemoveTraits(.isImage) // otherwise Voice Over will try to read text recognized in the image
    }

    /// Create a new device tile view.
    /// - Parameter deviceInfo: The paired device information.
    public init(_ deviceInfo: PairedDeviceInfo) {
        self.deviceInfo = deviceInfo
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    VStack(spacing: 0) {
        HStack(spacing: 16) {
            Group {
                DeviceTile(.mockHealthDevice2)
                DeviceTile(.mockHealthDevice1)
            }
#if canImport(UIKit)
                .background(Color(uiColor: .systemGroupedBackground))
#endif
                .frame(maxHeight: 190)
        }
        HStack(spacing: 16) {
            Group {
                DeviceTile(.mockHealthDevice2)
                DeviceTile(.mockHealthDevice1)
            }
#if canImport(UIKit)
                .background(Color(uiColor: .systemGroupedBackground))
#endif
                .frame(maxHeight: 190)
        }
    }
        .padding([.leading, .trailing], 12)
        .frame(maxHeight: .infinity)
#if canImport(UIKit)
        .background(Color(uiColor: .systemGroupedBackground))
#endif
        .previewWith {
            PairedDevices()
        }
}
#endif
