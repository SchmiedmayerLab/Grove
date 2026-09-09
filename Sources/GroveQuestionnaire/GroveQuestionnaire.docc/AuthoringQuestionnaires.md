# Authoring Questionnaires in Swift

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Declare an instrument's questions, branching, and scoring as Swift the compiler checks.


## Discussion

### The shape of an instrument

An instrument is a type — usually a caseless enum — that declares its questions as
`static let`s and places them in one ``Questionnaire``:

```swift
@Instrument
enum Screener {
    static let consent = BooleanQuestion("consent", "May we ask a few questions?")
    static let age = NumberQuestion.integer("age", "How old are you?")
        .range(0...120)
        .enabledWhen(consent.isTrue)

    static let questionnaire = Questionnaire(
        url: URL(string: "https://example.org/fhir/Questionnaire/screener")!,
        version: "1.0.0",
        title: "Screener"
    ) {
        Section("screening", title: "Screening") {
            consent
            age
        }
    }
}
```

A declared question is both the item in the questionnaire and the handle used to read its
answer and to condition on it. The first argument is its linkId — the stable identity
that travels to FHIR and back — so it is written explicitly rather than derived from the
Swift name.

``Instrument()`` is what makes the declarations checkable: it reads the type at build time
and reports what does not hold together. It also generates a `LinkID` enum
(`Screener.LinkID.age.rawValue == "age"`) and a ``DeclaredInstrument`` conformance for
``Questionnaire/checkDeclaration(of:)``.

### Sections and groups

A ``Questionnaire/Section`` is one page. A ``Group`` structures a page without splitting
it: it carries a title, it nests, and a condition on it gates everything inside at once.

```swift
Section("symptoms", title: "Your Symptoms") {
    Instruction("intro", "Over the **last two weeks**, how often…")

    Group("mood", title: "Mood") {
        interest
        hopelessness
    }
    .enabledWhen(consent.isTrue)
}
```

The section's title captions its page, and every named group captions the questions it
covers, outermost group first — so a name written at any depth reaches the participant.

``Instruction`` is text with no answer; its content is Markdown. Both builders accept `if`
and `for`, so a section can be assembled from configuration:

```swift
Section("extras") {
    if study.collectsMedication {
        medication
    }
    for day in 1...7 {
        BooleanQuestion("adherence-\(day)", "Did you take it on day \(day)?")
    }
}
```

The generated linkIds are still checked for uniqueness; only questions declared as
`static let`s can be referenced by name.

### Questions

| Declaration | Typed answer | FHIR item type |
| ----------- | ------------ | -------------- |
| ``Instruction`` | *none* | `display` |
| ``Group`` | *none* | `group` |
| ``BooleanQuestion`` | `Bool` | `boolean` |
| ``TextQuestion`` | `String` | `string` / `text` |
| ``NumberQuestion`` | `Double` | `decimal` |
| ``NumberQuestion/integer(_:_:)`` | `Double` | `integer` |
| ``NumberQuestion/quantity(_:_:unit:system:display:)`` | `Double` | `quantity` |
| ``DateQuestion`` | `DateComponents` | `date` |
| ``DateQuestion/time(_:_:)`` / ``DateQuestion/dateTime(_:_:)`` | `DateComponents` | `time` / `dateTime` |
| ``ChoiceQuestion`` | `Option` | `choice` |
| ``MultiChoiceQuestion`` | `Set<Option>` | `choice` with `repeats` |
| ``DynamicChoiceQuestion`` | `String` | `choice` |
| ``DynamicMultiChoiceQuestion`` | `Set<String>` | `choice` with `repeats` |

Each kind adds the modifiers that only make sense for it — `length(_:)`, `matching(_:)`
and `keyboard(_:)` on text; `range(_:)`, `slider(step:)` and `unitOptions(_:)` on numbers;
`dropDown()`, `autocomplete()`, `horizontal()` and `allowsOther(_:)` on choices. See
<doc:QuestionKinds> for the kinds themselves, including the ones an app defines.

Every component shares the modifiers below:

| Modifier | Effect |
| -------- | ------ |
| ``QuestionnaireComponent/optional(_:)`` | The participant may skip it (FHIR `required`) |
| ``QuestionnaireComponent/readOnly(_:)`` | Shown, not editable |
| ``QuestionnaireComponent/hidden(_:)`` | Kept in the response but never rendered |
| ``QuestionnaireComponent/enabledWhen(_:)`` | Shown only while the condition holds |
| ``QuestionnaireComponent/subtitle(_:)`` / ``QuestionnaireComponent/help(_:)`` | Secondary text, guidance below the item |
| ``QuestionnaireComponent/prefix(_:)`` / ``QuestionnaireComponent/shortTitle(_:)`` | Item numbering, abbreviated title |
| ``QuestionnaireComponent/media(_:)`` | An image alongside the question |
| ``QuestionnaireComponent/calculated(_:)`` | Continuously computed value (see below) |
| ``QuestionnaireComponent/constraint(_:message:)`` | Cross-field validation with an authored message |
| ``TypedQuestion/initialValue(_:)`` | A starting answer the participant can edit |

A ``Group`` collects no answer, so the modifiers that describe an answer are unavailable
on it — the error says which item to put them on instead.

### Typed options

The options of a ``ChoiceQuestion`` are the cases of a ``QuestionnaireOption`` type. The
raw values are the codes, `allCases` in declaration order is the exported `answerOption`
list, and `system` is the code system every case belongs to:

```swift
enum Severity: String, QuestionnaireOption {
    case noPain = "no-pain"
    case mild, moderate, severe

    static let system = URL(string: "https://example.org/fhir/CodeSystem/severity")

    var title: String {
        switch self {
        case .noPain: "No pain"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }
}
```

A question over the scale then carries only its linkId and its text:

```swift
static let pain = ChoiceQuestion<Severity>("pain", "How bad is the pain?")
```

Overriding `isExclusive` on a case makes selecting it clear every other selection — the
"None of the above" behavior of a ``MultiChoiceQuestion``.

When the options genuinely are not known until runtime — an `answerValueSet` resolved from
a server, a list assembled from data — use ``DynamicChoiceQuestion`` with ``Choice``
values. Nothing checks the codes there, so reach for it only when the closed set cannot be
written down.

### Conditions

Conditions are built from the questions themselves, so they cannot name an item or an
option that does not exist. Given a boolean `consent`, a numeric `age`, a text `nickname`
and a `ChoiceQuestion<Severity>` named `pain`:

```swift
consent.isTrue                        // and .isFalse
consent == false
age >= 18                             // numeric: == > >= < <=
nickname == "Ada"
pain.selected(.severe)                // checked against the option type
pain.answered                         // any answer at all
```

They compose with `&&`, `||` and `!`, and applying
``QuestionnaireComponent/enabledWhen(_:)`` more than once combines the conditions with
`&&`:

```swift
static let followUp = TextQuestion("follow-up", "What has been troubling you?")
    .enabledWhen(pain.selected(.severe) || pain.selected(.moderate))
    .enabledWhen(consent.isTrue)
    .optional()
```

Conditions may reference questions that come later in the questionnaire; they are resolved
across the whole instrument.

### Scoring

An option scale that scores conforms to ``ScoredOption``, which makes the weight a
requirement rather than an optional that silently defaults to nothing:

```swift
enum Frequency: String, ScoredOption {
    case notAtAll = "not-at-all"
    case severalDays = "several-days"
    case moreThanHalf = "more-than-half"
    case nearlyEveryDay = "nearly-every-day"

    static let system = URL(string: "https://example.org/fhir/CodeSystem/phq-scale")

    var title: String { /* … */ }

    var score: Decimal {
        switch self {
        case .notAtAll: 0
        case .severalDays: 1
        case .moreThanHalf: 2
        case .nearlyEveryDay: 3
        }
    }
}
```

A ``ScoreExpression`` is then built from the questions, not from a string naming them, and
compiles down to the SDC `calculatedExpression` FHIRPath:

```swift
static let total = NumberQuestion("total", "Total score")
    .calculated(.sumOfWeights(of: interest, mood))
    .readOnly()
    .hidden()

static let average = NumberQuestion("average", "Average")
    .calculated(.sumOfWeights(of: interest, mood) / .countAnswered(of: interest, mood))
    .readOnly()
    .hidden()
```

``ScoreExpression/sumOfAllWeights`` sums every scored answer in the questionnaire,
``ScoreExpression/constant(_:)`` contributes a literal, and the four arithmetic operators
combine them. Only questions over a ``ScoredOption`` are accepted, so a scale that forgot
its weights is a compile error rather than a form that quietly totals zero. For an
expression the constructors cannot build, ``ScoreExpression/raw(_:)`` takes FHIRPath —
still parsed at build time inside an ``Instrument()`` type.

Calculated values recompute as the participant answers, and ride into the exported
`QuestionnaireResponse` like any other answer.

Install the FHIR expression engine before presenting a questionnaire that contains calculated values or raw FHIRPath expressions:

```swift
import GroveQuestionnaireFHIR

let questionnaire = try Screener.questionnaire.withExpressionEngine()
```

Clock-sensitive expressions such as `today()` use the wall clock; pass `evaluationInstant:` to pin them to a fixed instant, for example when re-evaluating a stored submission.

### Reading the answers

``QuestionnaireResponses`` is subscripted by the declarations themselves:

```swift
let responses = QuestionnaireResponses(questionnaire: Screener.questionnaire, resuming: draft)

let consented = responses[Screener.consent]           // Bool?
let age = responses[Screener.age]                     // Double?
```

> Tip: When the answers are collected on screen, `QuestionnaireSheet` in `GroveQuestionnaireUI`
hands back the same ``QuestionnaireResponses`` to read exactly this way.

The subscript writes as well as reads, which is how a questionnaire is pre-populated from
data the app already holds. Handles erase to linkIds, so reading one out of a different
questionnaire's responses compiles and then answers `nil` forever; a debug assertion
catches that on first access.

### What the compiler catches

``Instrument()`` reads the declaration at build time and fails the build on:

- a linkId declared twice, pointing at both occurrences;
- a question declared but never placed in the questionnaire, or placed twice;
- a condition referencing a declaration that is not part of this questionnaire;
- an initializer cycle between declarations, which would otherwise deadlock on first access;
- more than one — or no — `Questionnaire(…)` in the type;
- malformed FHIRPath in a ``ScoreExpression/raw(_:)`` or ``QuestionnaireComponent/constraint(_:message:)``.

It warns, rather than fails, where it cannot see enough to be sure: a linkId that is not a
string literal, an item built by a helper the macro cannot read, an expression naming a
linkId the instrument does not declare, or a condition qualified by another instrument's
type. Each warning names exactly what went unchecked; the questionnaire still validates its
own identifiers when it is constructed.

The type system carries the rest. An option that is not on the scale, a score over an
unweighted question, a group given a modifier that only describes an answer, a bare string
or condition in a section body, a question written where a section belongs — each is a
compile error whose message says what to write instead.

### Questionnaires assembled from data

``Questionnaire/init(metadata:sections:)`` assumes its identifiers are unique and traps if
they are not, which is the right behavior for a declaration the macro already checked. For
content built from data — an imported FHIR resource, sections assembled at runtime — use
``Questionnaire/validated(metadata:sections:)``, which reports a
``Questionnaire/IntegrityError`` instead of trapping.

When the questionnaire comes from a server but the app was written against a Swift
declaration, check the two against each other once before reading answers:

```swift
try questionnaire.checkDeclaration(of: Screener.self)
```


## Topics

### Declaring an Instrument
- ``Instrument()``
- ``DeclaredInstrument``
- ``Questionnaire/checkDeclaration(of:)``

### Structure
- ``Questionnaire/Section``
- ``Group``
- ``Instruction``
- ``QuestionnaireBuilder``
- ``SectionContentBuilder``

### Questions
- ``QuestionnaireComponent``
- ``TypedQuestion``
- ``BooleanQuestion``
- ``TextQuestion``
- ``NumberQuestion``
- ``DateQuestion``
- ``ChoiceQuestion``
- ``MultiChoiceQuestion``
- ``DynamicChoiceQuestion``
- ``DynamicMultiChoiceQuestion``

### Options and Scoring
- ``QuestionnaireOption``
- ``ScoredOption``
- ``Choice``
- ``ScoredQuestion``
- ``ScoreExpression``

### Conditions
- ``Questionnaire/Condition``
