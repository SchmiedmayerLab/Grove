# Study Evolution

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Study Evolution
There are two kinds of possible changes the ``StudyDefinition`` type (as well as apps/libraries using it) must be able to cope with:
1. **Study Content Evolution:** changes made within a study; e.g., adding a new component, modifying an existing component, adjusting some component's schedule, etc.
2. **Study Definition Evolution:** changes made not to individual studies, but to the ``StudyDefinition`` type itself; e.g., adding/renaming/removing a property, changing a type, etc.

The SpeziStudy package and the ``StudyDefinition`` type provide facilities for dealing with both of these kinds of study evolution.

### Study Content Evolution
*Content Evolution* refers to all those changes that are made within one specific study definition, e.g. adding a new component, or adjusting some component's schedule.
The ``StudyDefinition/studyRevision`` property exists for tracking such changes; and should be incremented by `1` every time a changed version of a ``StudyDefinition`` is made available to an app.
SpeziStudy's [`StudyManager`](../../SpeziStudy/SpeziStudy.docc/SpeziStudy.md) uses this value to ensure the integrity of a user's study enrollments,
and to properly incurporate changes made to a study definition into the app's state.

### Study Definition Evolution
Changes made not to individual studies, but rather to the ``StudyDefinition`` type itself.
(E.g.: adding/removing/renaming a property somewhere, changing a type, or changing the way some aspect of the ``StudyDefinition`` is modelled and handled.)
Since the ``StudyDefinition`` type is explicitly designed to be encoded, decoded, persisted to disk, and transferred over the internet, there can be situations where an app attempts to read an encoded ``StudyDefinition`` that was created using an older version of the SpeziStudy library.
The ``StudyDefinition`` type uses the concept of a *schema version* to keep track of the different "versions" of the type itself.
For example, adding a new property somewhere within the ``StudyDefinition`` or one of its nested member types would necessitate an increase in the current schema version.
The schema version associated with the current structure of the ``StudyDefinition`` type can be accessed via ``StudyDefinition/schemaVersion-swift.type.property``.
This is [not something users will have to deal with; the package will try to take care of this for you]
The ``StudyDefinition``'s ``StudyDefinition/encode(to:)`` function adds an additional top-level entry into the encoded representation, which contains the
