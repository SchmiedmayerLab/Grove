# ``GroveSchedulerUI``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Present the schedule of a GroveScheduler.

## Overview

GroveSchedulerUI renders the events a [GroveScheduler](../../GroveScheduler/GroveScheduler.docc/GroveScheduler.md) produces as a list of tiles the user can act on.

@Row {
    @Column {
        @Image(source: "Schedule", alt: "The Schedule screen for today listing a weight measurement, lab results, and a questionnaire as tiles, each with its category, time, instructions, and an action button.") {
            ``EventScheduleList`` shows a day's events; each ``InstructionsTile`` carries the task's category, time, instructions, and its ``EventActionButton``.
        }
    }
    @Column {
        @Image(source: "ScheduleCentered", alt: "The same schedule with every tile centered and its More Information button written out under the header.") {
            Pass `alignment: .center` to an ``InstructionsTile`` to center its header and stretch the more-information link.
        }
    }
    @Column {
        @Image(source: "ScheduleTomorrow", alt: "The Schedule screen for tomorrow listing the tasks scheduled for that day.") {
            ``EventScheduleList`` takes any `date`, so the same view shows tomorrow or any other day.
        }
    }
    @Column {
        @Image(source: "EventDetails", alt: "A sheet titled More Information with the event's title, time and instructions.") {
            The info button on a tile opens the event's details in a sheet; the app decides what the sheet shows.
        }
    }
}


## Topics

### Card Layouts

- ``InstructionsTile``
- ``DefaultTileHeader``
- ``EventActionButton``

### Displaying Events

- ``EventScheduleList``

### Category Appearance
Control how the category information of a task should be rendered to the user.

- ``GroveScheduler/Task/Category/Appearance``
- ``SwiftUICore/View/taskCategoryAppearance(for:label:image:)``
- ``SwiftUICore/EnvironmentValues/taskCategoryAppearances``
- ``TaskCategoryAppearances``
