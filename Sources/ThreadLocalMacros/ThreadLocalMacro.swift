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
    // periphery:ignore - surfaced via String(describing:) in the compiler's macro-expansion diagnostic
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
    public static func expansion(
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
        // An optional stores its whole type, so `nil` is a value a thread can set; without an initializer it defaults to
        // `nil`, which the getter passes.
        let storage = typeAnnotation.type.threadLocalStorage
        if !storage.isOptional && binding.initializer == nil {
            throw DiagnosticsError(
                syntax: binding,
                message: "A non-optional type requires an initializer expression to provide a default value",
                id: .invalidSyntax
            )
        }

        let args = try initializerArguments(of: node)

        let attrs: AttributeSyntax? = variableDeclaration.isInlinable ? "@usableFromInline" : nil
        let modifiers = DeclModifierSyntax(name: variableDeclaration.isInlinable ? "internal" : "private")

        return [
            "\(attrs) \(modifiers) static let _\(identifier) = ThreadLocal<\(storage.type)>(\(args))"
        ]
    }

    /// The arguments the peer `ThreadLocal` is created with: the deallocator, when the attribute names one.
    private static func initializerArguments(of node: AttributeSyntax) throws -> LabeledExprListSyntax? {
        switch node.arguments {
        case nil:
            return nil
        case .argumentList(let arguments):
            guard let argument = arguments.first else {
                return nil // `@ThreadLocal()`
            }
            guard argument.label?.text == "deallocator" else {
                throw SimpleError("invalid args")
            }
            return [LabeledExprSyntax(label: "_deallocator", expression: argument.expression)]
        default:
            throw SimpleError("unexpected")
        }
    }
}


// MARK: Utils

extension TypeSyntax {
    /// The type a thread-local declared with this type stores, and whether it is an optional (`T?`, `T!`, `Optional<T>`
    /// or `Swift.Optional<T>`); an implicitly unwrapped `T!` stores `T?`, as `T!` is no generic argument.
    var threadLocalStorage: (type: TypeSyntax, isOptional: Bool) {
        if let unwrapped = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return (TypeSyntax(OptionalTypeSyntax(wrappedType: unwrapped.wrappedType.trimmed)), true)
        }
        if self.is(OptionalTypeSyntax.self) {
            return (trimmed, true)
        }
        if let named = self.as(IdentifierTypeSyntax.self), named.name.text == "Optional", named.genericArgumentClause != nil {
            return (trimmed, true)
        }
        if let member = self.as(MemberTypeSyntax.self),
           member.name.text == "Optional",
           member.genericArgumentClause != nil,
           member.baseType.trimmedDescription == "Swift" {
            return (trimmed, true)
        }
        return (trimmed, false)
    }
}


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
