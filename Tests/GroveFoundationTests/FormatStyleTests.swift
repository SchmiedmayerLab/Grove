//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import Testing


@Suite
struct FormatStyleTests {
    @Test
    func dateTimeDefaultBehaviours() throws {
        let timeZoneVatican = try #require(TimeZone(identifier: "Europe/Vatican"))
        let localeMicronesia = Locale(identifier: "en_FM")
        
        var style = Date.FormatStyle()
        #expect(style.locale == .autoupdatingCurrent)
        #expect(style.calendar == .autoupdatingCurrent)
        #expect(style.timeZone == .autoupdatingCurrent)
        
        style.timeZone = timeZoneVatican
        #expect(style.locale == .autoupdatingCurrent)
        #expect(style.calendar == .autoupdatingCurrent)
        
        style.locale = localeMicronesia
        #expect(style.calendar == .autoupdatingCurrent)
        #expect(style.timeZone == timeZoneVatican)
    }
    
    @Test
    func dateTimeExtensions() throws {
        let timeZoneVatican = try #require(TimeZone(identifier: "Europe/Vatican"))
        let localeMicronesia = Locale(identifier: "en_FM")
        let calendarBuddhist = Calendar(identifier: .buddhist)
        
        let style = Date.FormatStyle()
        
        #expect(style.locale == .autoupdatingCurrent)
        #expect(style.locale(localeMicronesia).locale == localeMicronesia)
        
        #expect(style.calendar == .autoupdatingCurrent)
        #expect(style.calendar(calendarBuddhist).calendar == calendarBuddhist)
        
        #expect(style.timeZone == .autoupdatingCurrent)
        #expect(style.timeZone(timeZoneVatican).timeZone == timeZoneVatican)
    }
}
