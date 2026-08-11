//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveViews
import SwiftUI


@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
struct NotificationTriggerLabel: View {
    private let nextTriggerDate: Date

    @ManagedViewUpdate private var viewUpdate

    var body: some View {
        Group {
            if nextTriggerDate > .now {
                Text("in \(Text(.currentDate, format: SystemFormatStyle.DateOffset(to: nextTriggerDate, sign: .never)))", bundle: .module)
            } else {
                Text("\(Text(.currentDate, format: SystemFormatStyle.DateOffset(to: nextTriggerDate, sign: .never))) ago", bundle: .module)
            }
        }
            .onAppear {
                viewUpdate.schedule(at: nextTriggerDate)
            }
    }

    init(_ nextTriggerDate: Date) {
        self.nextTriggerDate = nextTriggerDate
    }
}
