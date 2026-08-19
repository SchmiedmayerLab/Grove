//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import SwiftUI


struct SandboxDetectionTests: View {
    var body: some View {
        Form {
            Section {
                makeRow("Is running in Sandbox", value: ProcessInfo.isRunningInSandbox)
                makeRow("Is running in XCTest", value: ProcessInfo.isRunningInXCTest)
            }
        }
    }
    
    func makeRow(_ title: String, value: some CustomStringConvertible) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.description)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(title), \(value.description)")
    }
}
