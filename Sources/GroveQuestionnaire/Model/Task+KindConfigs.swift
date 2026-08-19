//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import UniformTypeIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task.Kind {
    /// Configuration of a free-text question.
    public struct FreeTextConfig: Hashable, Sendable {
        /// The on-screen keyboard suited to the expected entry (SDC `keyboard`).
        public enum KeyboardHint: String, Hashable, Sendable {
            case phone
            case email
            case number
            case url
        }

        /// The minimum allowed response length.
        public var minLength: Int?
        /// The maximum allowed response length.
        public var maxLength: Int?
        /// Response validation regular expression.
        public var regex: NSRegularExpression?
        /// Controls the response text field's autocorrection mode.
        public var disableAutocorrection: Bool
        /// Whether the response is a URL (FHIR item type `url`); the FHIR answer is then a `valueUri`.
        public var expectsURL: Bool
        /// The preferred on-screen keyboard.
        public var keyboard: KeyboardHint?
        /// Whether the answer runs to several lines (FHIR item type `text` rather than `string`).
        public var isMultiline: Bool

        public init(
            minLength: Int? = nil,
            maxLength: Int? = nil,
            regex: NSRegularExpression? = nil,
            disableAutocorrection: Bool = false,
            expectsURL: Bool = false,
            keyboard: KeyboardHint? = nil,
            isMultiline: Bool = false
        ) {
            self.minLength = minLength
            self.maxLength = maxLength
            self.regex = regex
            self.disableAutocorrection = disableAutocorrection
            self.expectsURL = expectsURL
            self.keyboard = keyboard
            self.isMultiline = isMultiline
        }
    }

    /// Configuration of a date/time question.
    public struct DateTimeConfig: Hashable, Sendable {
        public enum Style: Hashable, Sendable {
            case dateOnly
            case timeOnly
            case dateAndTime
        }
        /// The date picker's style
        public let style: Style
        /// The minimum allowed response value.
        public let minValue: DateComponents?
        /// The maximum allowed response value.
        public let maxValue: DateComponents?

        public init(style: Style, minValue: DateComponents? = nil, maxValue: DateComponents? = nil) {
            self.style = style
            self.minValue = minValue
            self.maxValue = maxValue
        }
    }

    /// Configuration of a number input question.
    public struct NumericTaskConfig: Hashable, Sendable {
        public enum NumberKind: Hashable, Sendable {
            case integer, decimal
        }
        public enum InputMode: Hashable, Sendable {
            case numberPad(NumberKind)
            case slider(stepValue: Double)
        }
        /// The FHIR value type the response is recorded as.
        public enum ValueKind: Hashable, Sendable {
            /// FHIR item type `integer`; answers are `valueInteger`.
            case integer
            /// FHIR item type `decimal`; answers are `valueDecimal`.
            case decimal
            /// FHIR item type `quantity`; answers are `valueQuantity`.
            case quantity
        }

        /// A unit the participant may choose among (FHIR `questionnaire-unitOption`).
        public struct UnitOption: Hashable, Sendable {
            /// The user-displayed unit label.
            public let display: String
            /// The unit's coding system (typically UCUM).
            public let system: URL?
            /// The unit's code within ``system``.
            public let code: String

            public init(display: String, system: URL? = nil, code: String) {
                self.display = display
                self.system = system
                self.code = code
            }
        }
        /// The preferred input mode.
        public let inputMode: InputMode
        /// The minimum allowed response value.
        public let minimum: Double?
        /// The maximum allowed response value.
        public let maximum: Double?
        /// The maximum allowed number of decimal places.
        public let maxDecimalPlaces: UInt?
        /// The user-displayed unit of the quantity being asked for.
        public let unit: String
        /// The unit's coded form (typically UCUM), carried into `valueQuantity.system`/`.code`.
        public let unitSystem: URL?
        /// The unit's code within ``unitSystem``.
        public let unitCode: String?
        /// The FHIR value type the response is recorded as.
        public let valueKind: ValueKind
        /// The units the participant may choose among; empty means the single
        /// fixed ``unit`` applies.
        public let unitOptions: [UnitOption]

        public init(
            inputMode: InputMode,
            minimum: Double? = nil,
            maximum: Double? = nil,
            maxDecimalPlaces: UInt? = nil,
            unit: String = "",
            unitSystem: URL? = nil,
            unitCode: String? = nil,
            valueKind: ValueKind = .decimal,
            unitOptions: [UnitOption] = []
        ) {
            self.inputMode = inputMode
            self.minimum = minimum
            self.maximum = maximum
            self.maxDecimalPlaces = maxDecimalPlaces
            self.unit = unit
            self.unitSystem = unitSystem
            self.unitCode = unitCode
            self.valueKind = valueKind
            self.unitOptions = unitOptions
        }
    }

    /// Configuration of a file selection question.
    public struct FileAttachmentConfig: Hashable, Sendable {
        /// The content types allowed for attachments.
        public let contentTypes: Set<UTType>
        /// The maximum file size allowed per attachment.
        public let maxSize: UInt64?
        /// Whether the user may select multiple attachments.
        public let allowsMultipleSelection: Bool

        public init(contentTypes: Set<UTType>, maxSize: UInt64? = nil, allowsMultipleSelection: Bool) {
            self.contentTypes = contentTypes
            self.maxSize = maxSize
            self.allowsMultipleSelection = allowsMultipleSelection
        }
    }

    /// Configuration of a single/multiple choice question.
    public struct ChoiceConfig: Hashable, Sendable {
        /// How the options are presented (FHIR `questionnaire-itemControl`).
        public enum Presentation: Hashable, Sendable {
            /// The standard option list (also used for `radio-button` and `check-box` hints).
            case list
            /// A compact menu (`drop-down`), suited to long option lists.
            case dropDown
            /// A type-ahead filter over the options (`autocomplete`).
            case autocomplete
        }

        /// The option layout direction (FHIR `questionnaire-choiceOrientation`).
        public enum Orientation: Hashable, Sendable {
            case vertical
            case horizontal
        }

        /// The options the user can select from.
        ///
        /// - Important: The options, as identified by their ``Option/id``s must be distinct.
        ///     If a `ChoiceConfig` contains multiple options with identical identifiers, the behaviour is undefined.
        public var options: [Option]
        /// Whether the user should be offered an "Other" option where they can enter arbitrary text.
        public var hasFreeTextOtherOption: Bool
        /// The label of the free-text "Other" option (SDC `openLabel`); `nil` uses the default.
        public var freeTextOtherOptionLabel: String?
        /// Whether the user is allowed to make multiple choices.
        public var allowsMultipleSelection: Bool
        /// How the options are presented.
        public var presentation: Presentation
        /// The option layout direction.
        public var orientation: Orientation
        /// The minimum number of selections required (FHIR `questionnaire-minOccurs`).
        public var minSelections: Int?
        /// The maximum number of selections allowed (FHIR `questionnaire-maxOccurs`).
        public var maxSelections: Int?
        /// A list of follow-up tasks.
        ///
        /// For every selected option in the choice question, the user will be asked to respond to all of the question's follow-up tasks.
        /// If the user deselects an option, its associated follow-up task responses will be discarded.
        public var followUpTasks: [Questionnaire.Task]

        public init(
            options: [Option],
            hasFreeTextOtherOption: Bool = false,
            freeTextOtherOptionLabel: String? = nil,
            allowsMultipleSelection: Bool,
            presentation: Presentation = .list,
            orientation: Orientation = .vertical,
            minSelections: Int? = nil,
            maxSelections: Int? = nil,
            followUpTasks: [Questionnaire.Task] = []
        ) {
            self.options = options
            self.hasFreeTextOtherOption = hasFreeTextOtherOption
            self.freeTextOtherOptionLabel = freeTextOtherOptionLabel
            self.allowsMultipleSelection = allowsMultipleSelection
            self.presentation = presentation
            self.orientation = orientation
            self.minSelections = minSelections
            self.maxSelections = maxSelections
            self.followUpTasks = followUpTasks
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task.Kind.ChoiceConfig {
    public struct Option: Hashable, Identifiable, Sendable {
        public struct FHIRCoding: Hashable, Sendable {
            public let system: URL
            public let code: String

            public init(system: URL, code: String) {
                self.system = system
                self.code = code
            }
        }

        /// A non-coding FHIR `answerOption` value the option was created from.
        public enum AnswerValue: Hashable, Sendable {
            case string(String)
            case integer(Int)
            case date(DateComponents)
            case time(DateComponents)
        }

        /// The option's identifier.
        ///
        /// Option identifiers must be unique within a single task. Options created from
        /// FHIR codings use the `system|code` token (or the bare code when the coding
        /// has no system) so that identical codes from different systems stay distinct.
        public let id: String
        public let title: String
        public let subtitle: String
        /// The option's FHIR coding, if it was created from one.
        public let fhirCoding: FHIRCoding?
        /// The option's non-coding FHIR value, if it was created from one.
        public let answerValue: AnswerValue?
        /// The option's scoring weight (FHIR `itemWeight`, or the retired `ordinalValue`).
        public let weight: Decimal?
        /// Whether selecting this option deselects all others (FHIR `questionnaire-optionExclusive`).
        public let isExclusive: Bool

        public init(
            id: String,
            title: String,
            subtitle: String = "",
            fhirCoding: FHIRCoding? = nil,
            answerValue: AnswerValue? = nil,
            weight: Decimal? = nil,
            isExclusive: Bool = false
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.fhirCoding = fhirCoding
            self.answerValue = answerValue
            self.weight = weight
            self.isExclusive = isExclusive
        }
    }
}
