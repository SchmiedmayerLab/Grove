//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftDiagnostics
public import SwiftSyntax
public import SwiftSyntaxMacros


private struct SimpleError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// Macro that defines a thread-local variable.
///
/// Generates get and set accessors to retrieve the value from the current thread.
/// The peer macro generates a `_` prefixed `ThreadLocal`.
public struct ThreadLocalMacro {}


extension ThreadLocalMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variableDeclaration = declaration.as(VariableDeclSyntax.self),
              let binding = variableDeclaration.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            return [] // diagnostics are provided by the peer macro expansion
        }
        guard variableDeclaration.isStatic else {
            throw DiagnosticsError(syntax: variableDeclaration, message: "@ThreadLocal property '\(identifier)' must be static", id: .invalidSyntax)
        }
        let getAccessor: AccessorDeclSyntax = if let initializer = binding.initializer {
            """
            @available(*, noasync) get {
                _\(identifier)._get(default: \(initializer.value))
            }
            """
        } else {
            """
            @available(*, noasync) get {
                _\(identifier)._get(default: nil)
            }
            """
        }
        let setAccessor: AccessorDeclSyntax =
        """
        @available(*, noasync) set {
            _\(identifier)._set(newValue)
        }
        """
        return [getAccessor, setAccessor]
    }
}


extension ThreadLocalMacro: PeerMacro {
    public static func expansion( // swiftlint:disable:this function_body_length cyclomatic_complexity
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else {
            throw DiagnosticsError(syntax: declaration, message: "'@ThreadLocal' can only be applied to a 'var' declaration", id: .invalidSyntax)
        }
        guard variableDeclaration.isStatic else {
            // not reporting an error here bc the other function above is already taking care of that.
            return []
        }
        guard let binding = variableDeclaration.bindings.first,
              variableDeclaration.bindings.count == 1 else {
            throw DiagnosticsError(
                syntax: declaration,
                message: "'@ThreadLocal' can only be applied to a 'var' declaration with a single binding",
                id: .invalidSyntax
            )
        }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            throw DiagnosticsError(
                syntax: declaration,
                message: "'@ThreadLocal' can only be applied to a 'var' declaration with a simple name",
                id: .invalidSyntax
            )
        }
        guard let typeAnnotation = binding.typeAnnotation else {
            throw DiagnosticsError(syntax: binding, message: "Variable binding is missing a type annotation", id: .invalidSyntax)
        }

        let valueTypeInitializer: TypeSyntax
        if let optionalType = typeAnnotation.type.as(OptionalTypeSyntax.self) {
            valueTypeInitializer = optionalType.wrappedType
        } else {
            valueTypeInitializer = typeAnnotation.type
            if binding.initializer == nil {
                throw DiagnosticsError(
                    syntax: binding,
                    message: "A non-optional type requires an initializer expression to provide a default value",
                    id: .invalidSyntax
                )
            }
        }

        let args: SwiftSyntax.LabeledExprListSyntax?
        switch node.arguments {
        case nil:
            args = nil
        case .argumentList(let argList):
            guard let arg = argList.first, arg.label?.text == "deallocator" else {
                throw SimpleError("invalid args")
            }
            args = [LabeledExprSyntax(label: "_deallocator", expression: arg.expression)]
        default:
            throw SimpleError("unexpected")
        }

        let attrs: AttributeSyntax? = variableDeclaration.isInlinable ? "@usableFromInline" : nil
        let modifiers = DeclModifierSyntax(name: variableDeclaration.isInlinable ? "internal" : "private")

        return [
            "\(attrs) \(modifiers) static let _\(identifier) = ThreadLocal<\(valueTypeInitializer.trimmed)>(\(args))"
        ]
    }
}


// MARK: Utils

extension VariableDeclSyntax {
    var isStatic: Bool {
        modifiers.contains { $0.name.trimmed.text == "static" }
    }
    var isInlinable: Bool {
        attributes.contains { $0.attribute?.attributeName.trimmed.as(IdentifierTypeSyntax.self)?.name.text == "inlinable" }
    }
}

extension AttributeListSyntax.Element {
    var attribute: AttributeSyntax? {
        switch self {
        case .attribute(let attr):
            attr
        case .ifConfigDecl:
            nil
        }
    }
}
