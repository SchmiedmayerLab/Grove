//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFoundation
import Testing


@Suite
struct DurationTests {
    @Test
    func factoryMethodsAndTimeInterval() throws {
        let minute: TimeInterval = 60
        let hour: TimeInterval = minute * 60
        let day: TimeInterval = hour * 24
        let week: TimeInterval = day * 7
        #expect(Duration.minutes(4).timeInterval == minute * 4)
        #expect(Duration.minutes(4.7).timeInterval == minute * 4.7)
        #expect(Duration.hours(4).timeInterval == hour * 4)
        #expect(Duration.hours(4.7).timeInterval == hour * 4.7)
        #expect(Duration.days(4).timeInterval == day * 4)
        #expect(Duration.days(4.7).timeInterval == day * 4.7)
        #expect(Duration.weeks(4 as Int).timeInterval == week * 4)
        #expect(Duration.weeks(4.7).timeInterval == week * 4.7)
    }
}
