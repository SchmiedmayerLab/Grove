//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Checks a questionnaire declaration as a whole: linkId uniqueness, that every declared
/// item is placed in the questionnaire, and that no two declarations reference each other.
///
/// ```swift
/// @Instrument
/// enum PHQ9 {
///     static let interest = ChoiceQuestion<Frequency>("phq9-1", "Little interest…")
///     static let sleep = ChoiceQuestion<Frequency>("phq9-3", "Trouble sleeping?")
///
///     static let questionnaire = Questionnaire(url: …, title: "PHQ-9") {
///         Section("phq9", title: "Over the last two weeks") {
///             interest
///             sleep
///         }
///     }
/// }
/// ```
///
/// The rule the checks follow: every referenceable item is a `static let` whose first
/// argument is a string-literal linkId, and each is placed exactly once in the
/// questionnaire body. Items written inline in the body are checked for uniqueness too;
/// they simply cannot be referenced by name.
///
/// Anything the macro cannot analyse — a loop building items, a helper function returning
/// components, a linkId that is not a literal — is reported as a warning naming what went
/// unchecked, and the questionnaire's own identifier check still catches collisions when it
/// is constructed.
@attached(member, names: named(LinkID))
@attached(extension, conformances: DeclaredInstrument, names: named(declaredLinkIDs))
public macro Instrument() = #externalMacro(module: "GroveQuestionnaireMacrosImpl", type: "InstrumentMacro")


/// A questionnaire declaration whose linkIds were checked at compile time by ``Instrument()``.
public protocol DeclaredInstrument {
    /// Every linkId the instrument declares, in declaration order.
    static var declaredLinkIDs: [String] { get }
}


// MARK: Runtime Bridge

@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// A questionnaire that does not match the Swift instrument it was checked against.
    public struct DeclarationMismatch: Error, CustomStringConvertible, Sendable {
        /// LinkIds the Swift declaration has that the questionnaire lacks — every typed
        /// handle among them reads as unanswered forever.
        public let missing: [String]
        /// LinkIds the questionnaire has that the Swift declaration does not.
        ///
        /// Reported for context only: an instrument declares just the items it names, so
        /// inline items and questions a server added are expected to show up here.
        public let unexpected: [String]

        public var description: String {
            "Questionnaire is missing \(missing.map { "'\($0)'" }.joined(separator: ", ")) declared by the instrument"
        }
    }

    /// Checks a runtime-constructed questionnaire against a Swift declaration, before typed
    /// handles are used to read answers out of it.
    ///
    /// Use this when the questionnaire comes from a server rather than from the Swift
    /// declaration itself — an imported FHIR resource that drifted from the instrument the
    /// app was written against otherwise surfaces as answers that are quietly always `nil`.
    public func checkDeclaration<Declaration: DeclaredInstrument>(
        of declaration: Declaration.Type
    ) throws(DeclarationMismatch) {
        let declared = Set(declaration.declaredLinkIDs)
        let present = allLinkIDs
        let missing = declared.subtracting(present)
        guard !missing.isEmpty else {
            return
        }
        throw DeclarationMismatch(missing: missing.sorted(), unexpected: present.subtracting(declared).sorted())
    }
}
