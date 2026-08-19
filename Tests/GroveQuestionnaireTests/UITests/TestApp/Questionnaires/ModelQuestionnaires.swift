//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import SwiftUI
import UniformTypeIdentifiers


/// Questionnaires written directly as model values — the form the DSL compiles to, and the
/// one a code generator or a server-driven form would produce.
extension Questionnaire {
    private static func metadata(_ id: String, _ title: String) -> Metadata {
        Metadata(
            id: "org.grovealliance.GroveQuestionnaire.demo.\(id)",
            url: URL(string: "https://grovealliance.org/questionnaires/demo/\(id)"),
            title: title,
            explainer: ""
        )
    }


    // MARK: Conditions

    /// A question that appears once the one above it is answered `true`.
    static let simpleCondition = Self(
        metadata: metadata("simple-condition", "Simple Condition"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "ice-cream", title: "Do you like Ice Cream?", kind: .boolean),
            .init(
                id: "ice-cream-flavor",
                title: "What's your favourite flavour?",
                kind: .choice(.init(
                    options: [
                        .init(id: "mango", title: "Mango"),
                        .init(id: "strawberry", title: "Strawberry")
                    ],
                    allowsMultipleSelection: false
                )),
                enabledCondition: .responseValueComparison(taskId: "ice-cream", operator: .equal, value: .bool(true))
            )
        ])]
    )

    /// The same condition, but reaching back to an answer given on an earlier page.
    static let crossSectionCondition = Self(
        metadata: metadata("cross-section-condition", "Cross-Section Condition"),
        sections: [
            .init(id: "s0", tasks: [
                .init(id: "ice-cream", title: "Do you like Ice Cream?", kind: .boolean)
            ]),
            .init(id: "s1", tasks: [
                .init(
                    id: "ice-cream-flavor",
                    title: "What's your favourite flavour?",
                    kind: .choice(.init(
                        options: [
                            .init(id: "mango", title: "Mango"),
                            .init(id: "strawberry", title: "Strawberry")
                        ],
                        allowsMultipleSelection: false
                    )),
                    enabledCondition: .responseValueComparison(taskId: "ice-cream", operator: .equal, value: .bool(true))
                )
            ]),
            .init(id: "s2", tasks: [
                .init(id: "thank-you", title: "Thank you", kind: .instructional("All Done!"))
            ])
        ]
    )

    /// A condition may look either way, as FHIR's `enableWhen` does: section A gates on a *later*
    /// question, section B on an earlier one, and both fire.
    static let conditionLookupRules = Self(
        metadata: metadata("condition-lookup-rules", "Test Condition Lookup Rules"),
        sections: [
            .init(id: "s0", tasks: [
                .init(id: "t0A", title: "Section A", kind: .instructional("")),
                .init(
                    id: "t1A",
                    title: "How much do you like green?",
                    kind: .choice(.init(
                        options: [
                            .init(id: "0", title: "A Lot"),
                            .init(id: "1", title: "A Little")
                        ],
                        allowsMultipleSelection: false
                    )),
                    enabledCondition: .responseValueComparison(taskId: "t2A", operator: .equal, value: .SCMCOption(id: "green"))
                ),
                .init(
                    id: "t2A",
                    title: "What's your favourite Colour?",
                    kind: .choice(.init(options: .colours, allowsMultipleSelection: false))
                )
            ]),
            .init(id: "s1", tasks: [
                .init(id: "t0B", title: "Section B", kind: .instructional("")),
                .init(
                    id: "t1B",
                    title: "What's your favourite Colour?",
                    kind: .choice(.init(options: .colours, allowsMultipleSelection: false))
                ),
                .init(
                    id: "t2B",
                    title: "How much do you like green?",
                    kind: .choice(.init(
                        options: [
                            .init(id: "0", title: "A Lot"),
                            .init(id: "1", title: "A Little")
                        ],
                        allowsMultipleSelection: false
                    )),
                    enabledCondition: .responseValueComparison(taskId: "t1B", operator: .equal, value: .SCMCOption(id: "green"))
                )
            ])
        ]
    )

    /// A follow-up task gated on another follow-up task of the same question.
    static let nestedQuestionCondition = Self(
        metadata: metadata("nested-question-condition", "Nested Question with Inner-Reference Condition"),
        sections: [.init(id: "s0", tasks: [
            .init(
                id: "t0",
                title: "Task A",
                kind: .choice(.init(
                    options: [
                        .init(id: "0", title: "Option 0"),
                        .init(id: "1", title: "Option 1")
                    ],
                    allowsMultipleSelection: true,
                    followUpTasks: [
                        .init(id: "it0", title: "Yes/No", kind: .boolean),
                        .init(
                            id: "it1",
                            title: "Conditional Inner Task with Inner reference",
                            kind: .instructional("This task should only be enabled if the previous task's response is 'true'"),
                            enabledCondition: .responseValueComparison(taskId: "it0", operator: .equal, value: .bool(true))
                        )
                    ]
                ))
            )
        ])]
    )

    /// When every follow-up of a selected option is disabled, the follow-up page is skipped.
    static let followUpTasksSkippedIfNoneEnabled = Self(
        metadata: metadata("follow-up-skipped", "Follow-Up Tasks Skipped if None Enabled"),
        sections: [
            .init(id: "s0", tasks: [
                .init(id: "t0", title: "Yes/No", kind: .boolean),
                .init(id: "t1", title: "Choice", kind: .choice(.init(
                    options: [
                        .init(id: "0", title: "Option 0"),
                        .init(id: "1", title: "Option 1")
                    ],
                    allowsMultipleSelection: true,
                    followUpTasks: [
                        .init(
                            id: "t1.1",
                            title: "Why?",
                            kind: .boolean,
                            enabledCondition: .responseValueComparison(taskId: "t0", operator: .equal, value: .bool(true))
                        )
                    ]
                )))
            ]),
            .init(id: "s1", tasks: [
                .init(
                    id: "t3",
                    title: "Section 2",
                    kind: .instructional("Reaching this page means the follow-up questions were skipped, as they should have been.")
                )
            ])
        ]
    )


    // MARK: Page Titles

    /// One page per shape a page can take when it names itself.
    ///
    /// `shortTitle` is SDC `shortText`, authored for a display too narrow for the text it stands
    /// for, and so the only thing that ever names the navigation bar. Every authored title reaches
    /// the page itself: the section's as the intro above the questions, a group's as the header
    /// over the run of questions it covers.
    static let pageTitles = Self(
        metadata: metadata("page-titles", "Page Titles"),
        sections: [
            .init(id: "mornings", tasks: [
                .init(id: "morning-note", title: "Morning routine", kind: .instructional(""), groupPath: [.mornings])
            ]),
            .init(id: "evenings", tasks: [
                .init(id: "evening-note", title: "Evening routine", kind: .instructional(""), groupPath: [.evenings])
            ]),
            .init(id: "week", title: "How would you describe a normal week for you?", shortTitle: "Your Week", tasks: [
                .init(id: "weekday-note", title: "On a workday", kind: .instructional(""), groupPath: [.weekdays]),
                .init(id: "weekend-note", title: "On a day off", kind: .instructional(""), groupPath: [.weekends])
            ]),
            .init(id: "around-the-clock", tasks: [
                .init(id: "daytime-note", title: "While you are up", kind: .instructional(""), groupPath: [.daytime]),
                .init(id: "sleep-note", title: "While you are asleep", kind: .instructional(""), groupPath: [.sleep])
            ]),
            .init(id: "check-in", tasks: [
                .init(id: "check-in-note", title: "Almost there", kind: .instructional(""), groupPath: [.checkIn])
            ]),
            .init(id: "unnamed", tasks: [
                .init(id: "unnamed-note", title: "Nothing named", kind: .instructional(""))
            ]),
            .init(id: "household", tasks: [
                .init(id: "people-note", title: "Who lives with you", kind: .instructional(""), groupPath: [.household, .people]),
                .init(id: "pets-note", title: "Who else lives with you", kind: .instructional(""), groupPath: [.household, .pets])
            ])
        ]
    )


    // MARK: Question Kinds

    /// Every kind the model offers, one question per page, including the choice variants the
    /// DSL cannot spell: follow-up tasks on both single- and multiple-select questions.
    static let inputKinds = Self(
        metadata: metadata("input-kinds", "Input Kinds"),
        sections: Task.allInputKinds.enumerated().map { Questionnaire.Section(id: "s\($0)", tasks: [$1]) }
    )

    /// Two numeric fields: integer and decimal entry through the number pad.
    static let simpleNumberEntry = Self(
        metadata: metadata("simple-number-entry", "Simple Number Entry"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "Integer Entry", kind: .numeric(.init(inputMode: .numberPad(.integer)))),
            .init(id: "t1", title: "Decimal Entry", kind: .numeric(.init(inputMode: .numberPad(.decimal))))
        ])]
    )

    /// A coded choice question that also accepts a free-text answer (FHIR `open-choice`).
    static let openChoice = Self(
        metadata: metadata("open-choice", "Open Choice"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "What's your favourite ice cream flavour?", kind: .choice(.init(
                options: [
                    .init(id: "0", title: "Mango"),
                    .init(id: "1", title: "Strawberry")
                ],
                hasFreeTextOtherOption: true,
                allowsMultipleSelection: false
            )))
        ])]
    )

    /// Display items render Markdown, including lists and paragraph breaks.
    static let markdownInstructions = Self(
        metadata: metadata("markdown-instructions", "Markdown Instructions"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "Instructions Title", kind: .instructional(
                """
                Consider doing any of the following to improve your health:
                - more sleep
                - less alcohol
                - no drugs

                Thanks for your attention!
                """
            ))
        ])]
    )

    /// A photo answer, which exports as a FHIR `Attachment`.
    static let fileAttachment = Self(
        metadata: metadata("file-attachment", "File Attachment"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "Photo Question", kind: .fileAttachment(.init(
                contentTypes: [.image],
                maxSize: nil,
                allowsMultipleSelection: false
            )))
        ])]
    )

    /// Marking named regions on a body map, drawn on top of a bundled image.
    static let annotateImage = Self(
        metadata: metadata("annotate-image", "Annotate Image"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "Where do you feel pain or stiffness?", kind: .annotateImage(.init(
                inputImage: .namedInMainBundle(filename: "legmap.png"),
                regions: [
                    .init(name: "Pain", color: .red),
                    .init(name: "Stiffness", color: .green)
                ]
            )))
        ])]
    )

    /// The same task with an image far taller than the screen, to exercise the zoom and fit.
    static let annotateTallImage = Self(
        metadata: metadata("annotate-tall-image", "Annotate Very Tall Image"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "Annotate Image", kind: .annotateImage(.init(
                inputImage: .namedInMainBundle(filename: "history.jpg"),
                regions: [
                    .init(name: "Pain", color: .red)
                ]
            )))
        ])]
    )


    // MARK: Custom Question Kinds

    /// A question kind supplied by the app: its own view, and a validation rule that keeps the
    /// section incomplete until the participant agrees.
    static let consentAcknowledgement = Self(
        metadata: metadata("consent-acknowledgement", "Consent Acknowledgement"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "Consent", kind: .custom(
                AcknowledgementQuestionKind.self,
                config: .init(
                    disclaimerText: "I consent that my data may be used for clinical research purposes.",
                    consentButtonTitle: "I Agree"
                )
            )),
            .init(id: "t1", title: "Do you like ice cream?", kind: .boolean)
        ])]
    )

    /// A custom kind that also encodes itself to FHIR, as a `Quantity` in seconds.
    static let stopwatch = Self(
        metadata: metadata("stopwatch", "Stopwatch"),
        sections: [.init(id: "s0", tasks: [
            .init(id: "t0", title: "How long did the walk take?", kind: .stopwatch)
        ])]
    )
}


extension Questionnaire.Task.Group {
    fileprivate static let mornings = Self(
        id: "mornings-group",
        title: "Everything you do before you leave the house",
        shortTitle: "Mornings"
    )
    fileprivate static let evenings = Self(id: "evenings-group", title: "Evening wind-down")
    fileprivate static let weekdays = Self(id: "weekdays-group", title: "Weekdays")
    fileprivate static let weekends = Self(id: "weekends-group", title: "Weekends")
    fileprivate static let daytime = Self(id: "daytime-group", title: "Daytime")
    /// Named by its short name alone, which is then the only name the page has for it.
    fileprivate static let sleep = Self(id: "sleep-group", shortTitle: "Sleep")
    /// Short name and title the same string, so heading the page would only repeat the bar.
    fileprivate static let checkIn = Self(id: "check-in-group", title: "Check-In", shortTitle: "Check-In")
    /// Encloses ``people`` and ``pets``, the way FHIR nests groups inside groups.
    fileprivate static let household = Self(id: "household-group", title: "Your Household")
    fileprivate static let people = Self(id: "people-group", title: "People")
    fileprivate static let pets = Self(id: "pets-group", title: "Pets")
}


extension [Questionnaire.Task.Kind.ChoiceConfig.Option] {
    fileprivate static let colours: Self = [
        .init(id: "red", title: "Red"),
        .init(id: "green", title: "Green"),
        .init(id: "blue", title: "Blue")
    ]

    fileprivate static let rgb: Self = [
        .init(id: "o1", title: "Red"),
        .init(id: "o2", title: "Green"),
        .init(id: "o3", title: "Blue")
    ]
}


extension Questionnaire.Task {
    fileprivate static let allInputKinds: [Self] = [
        .init(id: "taskInstructions", title: "Test Task: Instructions", kind: .instructional("Instructions Text")),
        .init(id: "taskBoolean", title: "Test Task: Boolean", kind: .boolean),
        .init(id: "taskDateTime", title: "Test Task: Date & Time", kind: .dateTime(.init(style: .dateAndTime))),
        .init(id: "taskDate", title: "Test Task: Date", kind: .dateTime(.init(style: .dateOnly))),
        .init(id: "taskTime", title: "Test Task: Time", kind: .dateTime(.init(style: .timeOnly))),
        .init(id: "taskText", title: "Test Task: Text", kind: .freeText(.init())),
        .init(id: "taskNumber1", title: "Test Task: Number (Pad)", kind: .numeric(.init(inputMode: .numberPad(.decimal)))),
        .init(id: "taskNumber2", title: "Test Task: Number (Slider)", kind: .numeric(.init(inputMode: .slider(stepValue: 1)))),
        .init(
            id: "taskChoice1",
            title: "Test Task: Choice (1)",
            subtitle: "Single-Choice, no follow-up tasks, no free-text option",
            kind: .choice(.init(options: .rgb, allowsMultipleSelection: false))
        ),
        .init(
            id: "taskChoice2",
            title: "Test Task: Choice (2)",
            subtitle: "Multiple-Choice, no follow-up tasks, no free-text option",
            kind: .choice(.init(options: .rgb, allowsMultipleSelection: true))
        ),
        .init(
            id: "taskChoice3",
            title: "Test Task: Choice (3)",
            subtitle: "Single-Choice, follow-up tasks, no free-text option",
            kind: .choice(.init(
                options: .rgb,
                allowsMultipleSelection: false,
                followUpTasks: .followUps(prefix: "taskChoice3")
            ))
        ),
        .init(
            id: "taskChoice4",
            title: "Test Task: Choice (4)",
            subtitle: "Multiple-Choice, follow-up tasks, no free-text option",
            kind: .choice(.init(
                options: .rgb,
                allowsMultipleSelection: true,
                followUpTasks: .followUps(prefix: "taskChoice4")
            ))
        ),
        .init(id: "taskAttachment", title: "Test Task: Attachment", kind: .fileAttachment(.init(
            contentTypes: [.image],
            allowsMultipleSelection: true
        )))
    ]
}


extension [Questionnaire.Task] {
    fileprivate static func followUps(prefix: String) -> Self {
        [
            .init(id: "\(prefix):fu1", title: "Yes? Or No?", kind: .boolean),
            .init(id: "\(prefix):fu2", title: "Boat? Or Paddle?", kind: .choice(.init(
                options: [.init(id: "o1", title: "Boat"), .init(id: "o2", title: "Paddle")],
                allowsMultipleSelection: false
            )))
        ]
    }
}
