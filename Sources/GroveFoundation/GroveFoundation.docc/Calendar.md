# Calendar

<!--
                  
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

Extensions on the `Calendar` and `TimeZone` types, implementing operations

## Topics

### Relative date calculations
- ``Foundation/Calendar/startOfHour(for:)``
- ``Foundation/Calendar/startOfNextHour(for:)``
- ``Foundation/Calendar/startOfNextDay(for:)``
- ``Foundation/Calendar/startOfPrevDay(for:)``
- ``Foundation/Calendar/startOfWeek(for:)``
- ``Foundation/Calendar/startOfNextWeek(for:)``
- ``Foundation/Calendar/startOfMonth(for:)``
- ``Foundation/Calendar/startOfNextMonth(for:)``
- ``Foundation/Calendar/startOfYear(for:)``
- ``Foundation/Calendar/startOfPrevYear(for:)``
- ``Foundation/Calendar/startOfNextYear(for:)``

### Determining component-based Date ranges
- ``Foundation/Calendar/rangeOfHour(for:)``
- ``Foundation/Calendar/rangeOfDay(for:)``
- ``Foundation/Calendar/rangeOfWeek(for:)``
- ``Foundation/Calendar/rangeOfMonth(for:)``
- ``Foundation/Calendar/rangeOfYear(for:)``

### Date distances
- ``Foundation/Calendar/countDistinctHours(from:to:)``
- ``Foundation/Calendar/countDistinctDays(from:to:)``
- ``Foundation/Calendar/countDistinctWeeks(from:to:)``
- ``Foundation/Calendar/countDistinctMonths(from:to:)``
- ``Foundation/Calendar/countDistinctYears(from:to:)``

### Other
- ``Foundation/Calendar/numberOfDaysInMonth(for:)``
- ``Foundation/Calendar/offsetInDays(from:to:)``

### Date FormatStyle
- ``Foundation/Date/FormatStyle/calendar(_:)``
- ``Foundation/Date/FormatStyle/timeZone(_:)``


### Time Zone

Improved DST handling for Foundation's TimeZone type.

- ``Foundation/TimeZone/DSTTransition``
- ``Foundation/TimeZone/nextDSTTransition(after:)``
- ``Foundation/TimeZone/nextDSTTransitions(maxCount:)``
- ``Foundation/TimeZone/losAngeles``
