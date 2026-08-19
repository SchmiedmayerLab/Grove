//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(macOS)
@testable import GroveQuestionnaireMacrosImpl
import SwiftParser
import SwiftSyntax
import Testing


@Suite
struct InstrumentMacroTests {}


extension InstrumentMacroTests {
    @Test
    func aWellFormedInstrumentIsSilent() {
        let result = check(
            """
            @Instrument
            enum Clean {
                static let intro = Instruction("intro", "Hello")
                static let mood = BooleanQuestion("mood", "Feeling well?")
                static let detail = TextQuestion("detail", "Tell us more")
                    .enabledWhen(mood.isFalse)
                static let questionnaire = Questionnaire(url: url, title: "Clean") {
                    Section("page") {
                        intro
                        mood
                        detail
                    }
                }
            }
            """
        )
        #expect(result.messages.isEmpty)
        #expect(result.linkIDs == ["intro", "mood", "detail"])
    }

    @Test
    func aDuplicateLinkIDIsAnError() {
        let messages = check(
            """
            @Instrument
            enum Duplicated {
                static let first = BooleanQuestion("q", "First?")
                static let second = BooleanQuestion("q", "Second?")
                static let questionnaire = Questionnaire(url: url, title: "D") {
                    Section("page") {
                        first
                        second
                    }
                }
            }
            """
        ).messages
        #expect(messages == [#"linkId "q" is declared twice; every item in a questionnaire needs its own linkId"#])
    }

    /// A section id and a task id share one namespace, because the exported FHIR puts them
    /// both in `linkId`.
    @Test
    func aSectionCannotShareAnIDWithATask() {
        let messages = check(
            """
            @Instrument
            enum Collide {
                static let mood = BooleanQuestion("page", "Feeling well?")
                static let questionnaire = Questionnaire(url: url, title: "C") {
                    Section("page") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages.count == 1)
        #expect(messages[0].hasPrefix(#"linkId "page" is declared twice"#))
    }

    /// The flagship catch: a question that exists in Swift, is referenced by a condition,
    /// and never reaches the participant.
    @Test
    func anUnplacedDeclarationIsAnError() {
        let messages = check(
            """
            @Instrument
            enum Forgotten {
                static let sleep = ChoiceQuestion<Frequency>("sleep", "Trouble sleeping?")
                static let mood = BooleanQuestion("mood", "Feeling well?")
                    .enabledWhen(sleep.answered)
                static let questionnaire = Questionnaire(url: url, title: "F") {
                    Section("page") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages == [
            "'sleep' is declared but never placed in the questionnaire",
            "condition references 'sleep', which is not part of this questionnaire"
        ])
    }

    @Test
    func placingAnItemTwiceIsAnError() {
        let messages = check(
            """
            @Instrument
            enum Twice {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                static let questionnaire = Questionnaire(url: url, title: "T") {
                    Section("one") {
                        mood
                    }
                    Section("two") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages == ["'mood' is placed twice; each item appears exactly once"])
    }

    /// `static let`s initialise through `swift_once`, so a reference cycle is a deadlock on
    /// first access rather than a logic error.
    @Test
    func aSelfReferencingConditionIsAnError() {
        let messages = check(
            """
            @Instrument
            enum Loop {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                    .enabledWhen(mood.isTrue)
                static let questionnaire = Questionnaire(url: url, title: "L") {
                    Section("page") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages == ["'mood' references itself in its own initializer, which deadlocks on first access"])
    }

    @Test
    func aMutualReferenceCycleIsAnError() {
        let messages = check(
            """
            @Instrument
            enum Mutual {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                    .enabledWhen(detail.answered)
                static let detail = TextQuestion("detail", "More?")
                    .enabledWhen(mood.isTrue)
                static let questionnaire = Questionnaire(url: url, title: "M") {
                    Section("page") {
                        mood
                        detail
                    }
                }
            }
            """
        ).messages
        #expect(messages == ["initializer cycle: 'mood' → 'detail' → 'mood'"])
    }
}


extension InstrumentMacroTests {
    @Test
    func anInstrumentNeedsExactlyOneQuestionnaire() {
        #expect(check(
            """
            @Instrument
            enum None {
                static let mood = BooleanQuestion("mood", "Feeling well?")
            }
            """
        ).messages.first == "@Instrument requires exactly one Questionnaire(…) declaration; found 0")
    }

    @Test
    func aMalformedExpressionIsAnError() {
        let messages = check(
            """
            @Instrument
            enum Broken {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                    .constraint("1 + )", message: "nope")
                static let questionnaire = Questionnaire(url: url, title: "B") {
                    Section("page") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages.count == 1)
        #expect(messages[0].hasPrefix("malformed FHIRPath: "))
    }

    @Test
    func anUnknownLinkIDInARawExpressionIsAWarning() {
        let messages = check(
            """
            @Instrument
            enum Stale {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                static let total = NumberQuestion("total", "Total")
                    .calculated(.raw("%resource.descendants().where(linkId='moood').answer.count()"))
                static let questionnaire = Questionnaire(url: url, title: "S") {
                    Section("page") {
                        mood
                        total
                    }
                }
            }
            """
        ).messages
        #expect(messages == [#"expression references linkId "moood", which this questionnaire does not declare"#])
    }

    /// A body the macro cannot read gives up on placement rather than guessing, and says so.
    @Test
    func anUnreadableBodySuppressesThePlacementChecks() {
        let messages = check(
            """
            @Instrument
            enum Looped {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                static let unplaced = TextQuestion("unplaced", "Never shown")
                static let questionnaire = Questionnaire(url: url, title: "L") {
                    Section("page") {
                        for index in 0..<3 {
                            BooleanQuestion("q\\(index)", "Question?")
                        }
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages == ["this item cannot be analysed; placement and uniqueness are not checked for this instrument"])
    }

    @Test
    func aNonLiteralLinkIDIsExcludedWithAWarning() {
        let messages = check(
            """
            @Instrument
            enum Computed {
                static let mood = BooleanQuestion(moodID, "Feeling well?")
                static let questionnaire = Questionnaire(url: url, title: "C") {
                    Section("page") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages == [
            "linkId is not a string literal; 'mood' is excluded from the checks",
            "cannot determine the linkId of 'mood'; it is excluded from the checks"
        ])
    }

    /// The macro cannot see another instrument's type, so a cross-instrument condition is a
    /// warning: it can say the reference leaves the questionnaire, not that it is wrong.
    @Test
    func aCrossInstrumentConditionIsAWarning() {
        let messages = check(
            """
            @Instrument
            enum Borrowing {
                static let mood = BooleanQuestion("mood", "Feeling well?")
                    .enabledWhen(GAD7.worry.isTrue)
                static let questionnaire = Questionnaire(url: url, title: "B") {
                    Section("page") {
                        mood
                    }
                }
            }
            """
        ).messages
        #expect(messages.count == 1)
        #expect(messages[0].hasPrefix("'GAD7.worry' is declared outside this instrument"))
    }

    /// Options and constants named through their type are not question references, and must
    /// not be mistaken for one.
    @Test
    func qualifiedOptionsAreNotMistakenForForeignQuestions() {
        let messages = check(
            """
            @Instrument
            enum Options {
                static let mood = ChoiceQuestion<Frequency>("mood", "How often?")
                static let detail = TextQuestion("detail", "More?")
                    .enabledWhen(mood.selected(Frequency.nearlyEveryDay))
                static let questionnaire = Questionnaire(url: url, title: "O") {
                    Section("page") {
                        mood
                        detail
                    }
                }
            }
            """
        ).messages
        #expect(messages.isEmpty)
    }
}


/// Runs the `@Instrument` checks over a source snippet and reports what they say.
private func check(_ source: String) -> (messages: [String], linkIDs: [String]) {
    let file = Parser.parse(source: source)
    guard let declaration = file.statements.compactMap({ $0.item.as(EnumDeclSyntax.self) }).first,
          let attribute = declaration.attributes.compactMap({ $0.as(AttributeSyntax.self) }).first else {
        return (["the snippet has no @Instrument enum"], [])
    }
    var analysis = InstrumentAnalysis(
        typeName: declaration.name.text,
        attribute: attribute,
        members: declaration.memberBlock.members
    )
    analysis.run()
    return (analysis.diagnostics.map(\.message), analysis.declaredLinkIDs.map(\.linkID))
}
#endif
