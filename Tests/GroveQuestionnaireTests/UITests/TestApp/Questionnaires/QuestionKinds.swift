//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import ModelsR4


enum SongOfIceAndFireBook: String, QuestionnaireOption {
    case gameOfThrones = "agot"
    case clashOfKings = "acok"
    case stormOfSwords = "asos"
    case feastForCrows = "affc"
    case danceWithDragons = "adwd"

    var title: String {
        switch self {
        case .gameOfThrones: "A Game of Thrones"
        case .clashOfKings: "A Clash of Kings"
        case .stormOfSwords: "A Storm of Swords"
        case .feastForCrows: "A Feast for Crows"
        case .danceWithDragons: "A Dance with Dragons"
        }
    }
}


/// Every question kind the DSL spells, one page per family.
///
/// Also the place to see what the modifiers do to a rendered question: a free-text answer
/// bounded by ``TextQuestion/length(_:)``, one validated against a regular expression, a
/// number rendered as a slider, and a quantity that carries its UCUM unit into the response.
@Instrument
enum QuestionKinds {
    static let intro = Instruction("intro", "These are **Markdown** instructions.")

    static let flavour = ChoiceQuestion<IceCreamFlavour>("flavour", "Single choice")
        .subtitle("What's your favourite ice cream flavour?")
        .allowsOther()

    static let books = MultiChoiceQuestion<SongOfIceAndFireBook>("books", "Multiple choice")
        .subtitle("Which of these have you read?")
        .optional()

    static let continent = DynamicChoiceQuestion("continent", "Drop-down", choices: [
        Choice("af", "Africa"),
        Choice("an", "Antarctica"),
        Choice("as", "Asia"),
        Choice("eu", "Europe"),
        Choice("na", "North America"),
        Choice("oc", "Oceania"),
        Choice("sa", "South America")
    ])
    .subtitle("Options given as values rather than as a Swift type.")
    .dropDown()

    static let agrees = BooleanQuestion("agrees", "Boolean")
        .subtitle("Have you answered honestly so far?")

    static let about = TextQuestion("about", "Free text")
        .subtitle("Tell us a little about yourself.")
        .length(3...280)
        .multiline()

    static let website = TextQuestion("website", "Validated text")
        // FHIR regexes are anchored, so the pattern has to cover the path and query too,
        // or every address but a bare host is rejected. Schemes and hosts are case-insensitive,
        // so HTTPS://Example.org is a perfectly good address and must not be rejected.
        .matching(try! NSRegularExpression(
            pattern: #"https?://[a-z0-9.-]+\.[a-z]{2,}(/\S*)?"#,
            options: [.caseInsensitive]
        ))
        .subtitle("Rejected until it looks like a link.")
        .keyboard(.url)
        .optional()

    static let day = DateQuestion("day", "Date")
    static let moment = DateQuestion.time("moment", "Time")
    static let dayAndMoment = DateQuestion.dateTime("day-and-moment", "Date and time")

    static let rating = NumberQuestion("rating", "Decimal, as a slider")
        .range(-5...12)
        .slider(step: 0.25)

    static let decimal = NumberQuestion("decimal", "Decimal, as a field")
        .range(-5...12)

    static let count = NumberQuestion.integer("count", "Integer, as a field")
        .range(0...12)
        .help("Whole numbers only.")

    static let acceleration = NumberQuestion.quantity("acceleration", "Quantity", unit: "m/s2", display: "m/s²")
        .range(0...50)

    static let questionnaire = Questionnaire(
        url: URL(string: "https://grovealliance.org/samples/QuestionKinds")!,
        version: "1.0.0",
        title: "Question Kinds",
        explainer: "A page each of text and choice, dates, and numbers."
    ) {
        Section("text", title: "Text & Choice") {
            intro
            flavour
            books
            continent
            agrees
            about
            website
        }
        Section("dates", title: "Dates & Times") {
            day
            moment
            dayAndMoment
        }
        Section("numbers", title: "Numbers") {
            rating
            decimal
            count
            acceleration
        }
    }
}
