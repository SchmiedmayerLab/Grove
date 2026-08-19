//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Algorithms
private import SwiftDiagnostics
public import SwiftSyntax
public import SwiftSyntaxMacros


/// The `@SynthesizeDisplayPropertyMacro` macro.
public enum SynthesizeDisplayPropertyMacro {
    /// The code written when the platform reports a value this build does not know.
    ///
    /// Hyphenated, so it can never collide with a Swift case name, and published as a
    /// code of every generated system — which is what keeps those systems `#complete`.
    static let unrecognizedValueCode = "unrecognized-platform-value"
    static let unrecognizedValueDisplay = "unrecognized platform value"
}

extension SynthesizeDisplayPropertyMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let argsList = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw MacroExpansionErrorMessage("missing arguments?")
        }
        let typeName = try Self.typeName(from: argsList)
        let caseNames = try Self.caseNames(from: argsList)
        let displayProperty = try Self.displayProperty(cases: caseNames)
        let codeProperty = try Self.codeProperty(cases: caseNames)
        // The code system's name, derived mechanically from the type's full name so a
        // renamed or nested type cannot silently change (or collide with) a system URL.
        let systemNameProperty = try VariableDeclSyntax(
            "static var fhirSystemName: String { \"\(raw: Self.systemName(forTypeNamed: typeName))\" }"
        )
        let systemTitleProperty = try VariableDeclSyntax(
            "static var fhirSystemTitle: String { \"\(raw: Self.systemTitle(forTypeNamed: typeName))\" }"
        )
        let platformTypeNameProperty = try VariableDeclSyntax(
            "static var fhirPlatformTypeName: String { \"\(raw: typeName)\" }"
        )
        // Every code this type can write, so the vocabulary generator publishes the
        // framework's own values instead of re-deriving them from the source.
        let publishedCodes = caseNames.map { "(\"\($0)\", \"\(displayText(for: $0))\")" }
            + ["(\"\(Self.unrecognizedValueCode)\", \"\(Self.unrecognizedValueDisplay)\")"]
        let publishedCodesProperty = try VariableDeclSyntax(
            "static var fhirPublishedCodes: [(code: String, display: String)] { [\(raw: publishedCodes.joined(separator: ", "))] }"
        )
        return [
            DeclSyntax(fromProtocol: displayProperty),
            DeclSyntax(fromProtocol: codeProperty),
            DeclSyntax(fromProtocol: systemNameProperty),
            DeclSyntax(fromProtocol: systemTitleProperty),
            DeclSyntax(fromProtocol: platformTypeNameProperty),
            DeclSyntax(fromProtocol: publishedCodesProperty)
        ]
    }

    /// Extracts `HKFoo` from the macro's leading `HKFoo.self` argument.
    private static func typeName(from argsList: LabeledExprListSyntax) throws -> String {
        guard let first = argsList.first?.expression.as(MemberAccessExprSyntax.self),
              let base = first.base else {
            throw MacroExpansionErrorMessage("First argument must be a metatype expression (e.g. `HKFoo.self`)")
        }
        return base.trimmedDescription
    }

    /// The enum cases the macro was applied to, spelled either as `.case` or as a string literal.
    private static func caseNames(from argsList: LabeledExprListSyntax) throws -> [String] {
        try argsList.dropFirst().map { syntax in
            if let syntax = syntax.expression.as((MemberAccessExprSyntax.self)) {
                return syntax.declName.baseName.text
            } else if let syntax = syntax.expression.as(StringLiteralExprSyntax.self) {
                return try syntax.segments.reduce(into: "") { partialResult, segment in
                    switch segment {
                    case .stringSegment(let segment):
                        partialResult.append(contentsOf: segment.content.text)
                    case .expressionSegment:
                        throw MacroExpansionErrorMessage("Argument String isn't allowed to contain interpolations!")
                    }
                }
            } else {
                throw MacroExpansionErrorMessage("Arhument must be an enum case expression!")
            }
        }
    }

    private static func displayProperty(cases caseNames: [String]) throws -> VariableDeclSyntax {
        try VariableDeclSyntax("var display: String?") {
            SwitchExprSyntax(subject: "self" as ExprSyntax) {
                for name in caseNames {
                    .switchCase(SwitchCaseSyntax("case .\(raw: name):") {
                        #""\#(raw: displayText(for: name))""#
                    })
                }
                SwitchCaseListSyntax.Element.switchCase(SwitchCaseSyntax("@unknown default:") {
                    #""\#(raw: Self.unrecognizedValueDisplay)""# as ExprSyntax
                })
            }
        }
    }

    /// The FHIR code is the Swift case name: stable, self-describing, and
    /// independent of the platform's raw integer values, which Apple may reassign.
    private static func codeProperty(cases caseNames: [String]) throws -> VariableDeclSyntax {
        try VariableDeclSyntax("var code: String") {
            SwitchExprSyntax(subject: "self" as ExprSyntax) {
                for name in caseNames {
                    .switchCase(SwitchCaseSyntax("case .\(raw: name):") {
                        #""\#(raw: name)""#
                    })
                }
                SwitchCaseListSyntax.Element.switchCase(SwitchCaseSyntax("@unknown default:") {
                    #""\#(raw: Self.unrecognizedValueCode)""# as ExprSyntax
                })
            }
        }
    }

    /// `HKCategoryValueSleepAnalysis` → `healthkit-category-value-sleep-analysis`.
    ///
    /// Nested types are flattened to the name Objective-C imports them under
    /// (`HKStateOfMind.Kind` → `HKStateOfMindKind`), so a system URL never depends on
    /// how the type is spelled at the use site.
    private static func systemName(forTypeNamed typeName: String) -> String {
        "healthkit-" + words(of: platformName(forTypeNamed: typeName)).map { $0.lowercased() }.joined(separator: "-")
    }

    /// `HKAppleECGAlgorithmVersion` → `HealthKit Apple ECG Algorithm Version`.
    private static func systemTitle(forTypeNamed typeName: String) -> String {
        "HealthKit " + words(of: platformName(forTypeNamed: typeName)).joined(separator: " ")
    }

    private static func platformName(forTypeNamed typeName: String) -> String {
        var name = String(typeName.filter { $0 != "." })
        if name.hasPrefix("HK") {
            name.removeFirst(2)
        }
        return name
    }

    private static func displayText(for enumCaseName: String) -> String {
        words(of: enumCaseName)
            .map { word in
                // "asleepREM" becomes "asleep REM": an acronym keeps its capitals.
                word.allSatisfy(\.isUppercase) ? word : word.lowercased()
            }
            .joined(separator: " ")
    }

    /// Splits a camel-cased platform name into its words.
    ///
    /// A word starts at an uppercase letter that follows a lowercase letter or a digit,
    /// or that ends a run of capitals (`AppleECGAlgorithm` → `Apple`, `ECG`,
    /// `Algorithm`). Digits belong to the word they follow, so `VO2MaxTestType` splits
    /// as `VO2`, `Max`, `Test`, `Type` and `maxExercise60Minute` keeps `Exercise60`.
    private static func words(of name: String) -> [String] {
        let characters = Array(name)
        let wordStarts = characters.indices.filter { index in
            guard index > 0, characters[index].isUppercase else {
                return index == 0
            }
            let previous = characters[index - 1]
            if previous.isLowercase || previous.isNumber {
                return true
            }
            return previous.isUppercase && characters.indices.contains(index + 1) && characters[index + 1].isLowercase
        }
        return chain(wordStarts, CollectionOfOne(characters.count))
            .adjacentPairs()
            .map { String(characters[$0..<$1]) }
    }
}
