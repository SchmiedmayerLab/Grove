//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros


/// The `@Instrument` macro.
///
/// The expansion is purely additive — a `LinkID` enum and a `DeclaredInstrument`
/// conformance — and never throws. Everything it finds wrong is reported as a diagnostic,
/// so a questionnaire that fails a check still compiles far enough to show the one real
/// error rather than a file full of "cannot find in scope".
public enum InstrumentMacro {
    private static let keywords: Set<String> = [
        "associatedtype", "case", "class", "default", "deinit", "enum", "extension", "false", "for", "func",
        "import", "in", "init", "internal", "let", "nil", "operator", "private", "protocol", "public", "repeat",
        "return", "self", "static", "struct", "subscript", "switch", "true", "typealias", "var", "where", "while"
    ]

    fileprivate static func analysis(
        of declaration: some DeclGroupSyntax,
        attribute: AttributeSyntax
    ) -> InstrumentAnalysis {
        var analysis = InstrumentAnalysis(
            typeName: declaration.asProtocol((any NamedDeclSyntax).self)?.name.text ?? "",
            attribute: attribute,
            members: declaration.memberBlock.members
        )
        analysis.run()
        return analysis
    }

    /// The access level the generated declarations adopt, so a public instrument keeps a
    /// public conformance.
    fileprivate static func accessLevel(of declaration: some DeclGroupSyntax) -> String {
        let levels: Set<TokenKind> = [.keyword(.public), .keyword(.package), .keyword(.open)]
        guard let modifier = declaration.modifiers.first(where: { levels.contains($0.name.tokenKind) }) else {
            return ""
        }
        return "\(modifier.name.text == "open" ? "public" : modifier.name.text) "
    }

    fileprivate static func availability(of declaration: some DeclGroupSyntax) -> String {
        declaration.attributes
            .compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription == "available" }
            .map { "\($0.trimmedDescription)\n" }
            .joined()
    }

    fileprivate static func caseName(for name: String) -> String {
        name.hasPrefix("`") || !keywords.contains(name) ? name : "`\(name)`"
    }

    fileprivate static func literal(_ value: String) -> String {
        value.replacingOccurrences(of: #"\"#, with: #"\\"#).replacingOccurrences(of: "\"", with: #"\""#)
    }
}


extension InstrumentMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let analysis = analysis(of: declaration, attribute: node)
        for diagnostic in analysis.diagnostics {
            context.diagnose(diagnostic)
        }
        guard !analysis.declaredLinkIDs.isEmpty else {
            // A raw-value enum needs at least one case, and an instrument that declares
            // nothing checkable gets an empty `declaredLinkIDs` instead.
            return []
        }
        let cases = analysis.declaredLinkIDs
            .map { "case \(caseName(for: $0.name)) = \"\(literal($0.linkID))\"" }
            .joined(separator: "\n")
        return [
            """
            \(raw: accessLevel(of: declaration))enum LinkID: String, CaseIterable, Hashable, Sendable {
                \(raw: cases)
            }
            """
        ]
    }
}


extension InstrumentMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else {
            return []
        }
        // Diagnostics belong to the member role; reporting them from both would double them.
        let body = analysis(of: declaration, attribute: node).declaredLinkIDs.isEmpty
            ? "[]"
            : #"LinkID.allCases.map(\.rawValue)"#
        let extensionDeclaration: DeclSyntax = """
            \(raw: availability(of: declaration))extension \(type.trimmed): DeclaredInstrument {
                \(raw: accessLevel(of: declaration))static var declaredLinkIDs: [String] {
                    \(raw: body)
                }
            }
            """
        return [extensionDeclaration.cast(ExtensionDeclSyntax.self)]
    }
}
