//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire


/// A stable authored instant shared by tests that are not specifically exercising timestamps.
let questionnaireResponseTestAuthoredAt = Date(timeIntervalSince1970: 1_700_000_000)
let questionnaireResponseTestTimeZone = TimeZone(secondsFromGMT: 0)! // swiftlint:disable:this force_unwrapping
/// The clock tests evaluate at when they are not specifically exercising time: `authored`, in its zone.
let questionnaireResponseTestClock = QuestionnaireClock.fixed(at: questionnaireResponseTestAuthoredAt, in: questionnaireResponseTestTimeZone)
