//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveQuestionnaire
public import ModelsR4


extension QuestionnaireClock {
    /// The instant a stored response was authored, in the offset `authored` carries.
    ///
    /// Every later evaluation of the response reads this clock, so it yields the same values and the same
    /// enablement on any device.
    public static func authored(_ response: ModelsR4.QuestionnaireResponse) throws(ContractError) -> Self {
        guard let authored = response.authored?.value else {
            throw .missingAuthored
        }
        guard authored.time != nil, let timeZone = authored.timeZone, let instant = try? authored.asNSDate() else {
            throw .authoredWithoutOffset
        }
        return .fixed(at: instant, in: timeZone)
    }
}
