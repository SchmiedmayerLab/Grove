//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Battery Icon with optional label.
public struct BatteryIcon: View {
    private let percentage: Int
    private let isCharging: Bool


    public var body: some View {
        Label {
            Text(verbatim: "\(percentage) %")
        } icon: {
            batteryIcon // hides accessibility, only text will be shown
                .foregroundStyle(.primary)
        }
            .accessibilityRepresentation {
                if !isCharging {
                    Text(verbatim: "\(percentage) %")
                } else {
                    Text("\(percentage) %, is charging", bundle: .module)
                }
            }
    }


    @ViewBuilder private var batteryIcon: some View {
        Group {
            if isCharging {
                Image(systemName: "battery.100percent.bolt")
            } else if percentage >= 90 {
                Image(systemName: "battery.100")
            } else if percentage >= 65 {
                Image(systemName: "battery.75")
            } else if percentage >= 40 {
                Image(systemName: "battery.50")
            } else if percentage >= 15 {
                Image(systemName: "battery.25")
            } else if percentage > 3 {
                Image(systemName: "battery.25")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .primary)
            } else {
                Image(systemName: "battery.0")
                    .foregroundColor(.red)
            }
        }
            .accessibilityHidden(true)
    }


    /// Create a new battery icon with charging indication.
    /// - Parameters:
    ///   - percentage: The current battery percentage.
    ///   - isCharging: Indicate if the device is currently charging.
    public init(percentage: Int, isCharging: Bool) {
        self.percentage = percentage
        self.isCharging = isCharging
    }

    /// Create a new battery icon.
    /// - Parameter percentage: The current battery percentage.
    public init(percentage: Int) {
        // isCharging=false is the same behavior as having no charging information
        self.init(percentage: percentage, isCharging: false)
    }
}


#if DEBUG
#Preview {
    BatteryIcon(percentage: 100)
}

#Preview {
    BatteryIcon(percentage: 85, isCharging: true)
}

#Preview {
    BatteryIcon(percentage: 70)
}

#Preview {
    BatteryIcon(percentage: 50)
}

#Preview {
    BatteryIcon(percentage: 25)
}

#Preview {
    BatteryIcon(percentage: 10)
}
#endif
