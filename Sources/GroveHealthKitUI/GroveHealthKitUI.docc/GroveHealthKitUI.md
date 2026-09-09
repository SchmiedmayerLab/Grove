# ``GroveHealthKitUI``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Visualize Health data in your app


## Overview

Use GroveHealthKitUI's ``HealthChart`` to visualize health data queried via [`GroveHealthKit`](../../GroveHealthKit/GroveHealthKit.docc/GroveHealthKit.md).

@Row(numberOfColumns: 4) {
    @Column {
        @Image(source: "HealthChart", alt: "A line chart of a week of heart rate and blood oxygen samples, one colored line per type with a legend below.") {
            ``HealthChart`` draws every query it is given as its own line and redraws as the store changes.
        }
    }
}

## Topics

### Querying Health Data in SwiftUI
- ``HealthKitQuery``
- ``HealthKitStatisticsQuery``
- ``HealthKitQueryResults``
- ``HealthKitCharacteristicQuery``

### Visualizing Queried Health Data
- ``HealthChart``

### ``HealthChart``
