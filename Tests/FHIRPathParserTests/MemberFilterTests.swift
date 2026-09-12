//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRPathParser
import Foundation
import Testing


/// `where` over a member and string literals is answered from the member directly; these pin that it finds
/// exactly what evaluating the criteria on every element finds.
@Suite
struct MemberFilterTests {
    private static let json = """
    {
        "resourceType": "QuestionnaireResponse",
        "item": [
            { "linkId": "a", "answer": [{ "valueCoding": { "code": "yes" } }, { "valueString": "yes" }] },
            { "linkId": "b", "answer": [{ "valueCoding": { "code": "no" } }],
              "item": [{ "linkId": "b.1", "answer": [{ "valueCoding": { "code": "yes" } }] }] },
            { "linkId": ["c", "d"] },
            { "text": "no linkId" },
            { "linkId": 7 }
        ]
    }
    """

    private static func context() throws -> FHIRPathEvaluationContext {
        let node = try FHIRPathNode(jsonData: Data(json.utf8))
        return FHIRPathEvaluationContext(focus: [.object(node)], constants: ["resource": [.object(node)]])
    }

    /// The parsed expression has to outlive the filter's reading of it: ANTLR's tokens read their text lazily.
    private static func filter(_ criteria: String) throws -> MemberFilter? {
        let parsed = try FHIRPathExpression.parse(criteria)
        return withExtendedLifetime(parsed) { MemberFilter(criteria: parsed.tree) }
    }

    private static func linkIds(_ expression: String, cache: FHIRPathDescendantsCache? = nil) throws -> [String] {
        var context = try context()
        context.descendants = cache
        return try FHIRPathExpression.evaluate(expression: expression, context: context).compactMap { value in
            if case .object(let node) = value {
                node.stringMember("linkId")
            } else {
                nil
            }
        }
    }

    @Test
    func recognisesTheCriteria() throws {
        let filter = try Self.filter("linkId = 'a' or (linkId = 'b' or linkId = 'c')")
        #expect(filter?.member == "linkId")
        #expect(filter?.literals == ["a", "b", "c"])
        #expect(try Self.filter("linkId = 'a' or code = 'b'") == nil, "one member only")
        #expect(try Self.filter("linkId != 'a'") == nil)
        #expect(try Self.filter("linkId = %x") == nil)
        #expect(try Self.filter("Patient = 'a'") == nil, "a type name is not a member")
        #expect(try Self.filter("linkId = 'a' and linkId = 'b'") == nil)
    }

    @Test
    func findsItemsByLinkId() throws {
        #expect(try Self.linkIds("%resource.descendants().where(linkId = 'a')") == ["a"])
        #expect(try Self.linkIds("%resource.descendants().where(linkId = 'b' or linkId = 'b.1')") == ["b", "b.1"])
        #expect(try Self.linkIds("%resource.item.where(linkId = 'a' or linkId = 'nope')") == ["a"])
    }

    /// With the descendants kept, `descendants().where(member = ...)` is answered from an index of the member.
    @Test
    func findsKeptDescendantsTheSameWay() throws {
        let cache = FHIRPathDescendantsCache(constants: ["questionnaire"], parent: .init(constants: ["resource"]))
        for _ in 0..<2 {
            #expect(try Self.linkIds("%resource.descendants().where(linkId = 'a')", cache: cache) == ["a"])
            #expect(try Self.linkIds("%resource.descendants().where(linkId = 'b.1' or linkId = 'b')", cache: cache) == ["b", "b.1"])
            #expect(try Self.linkIds("%resource.descendants().where(linkId = 'c')", cache: cache).isEmpty)
            #expect(try Self.linkIds("%resource.descendants().where(text = 'no linkId')", cache: cache).isEmpty)
            #expect(try Self.linkIds("%resource.descendants().where(linkId = 'nope')", cache: cache).isEmpty)
        }
        let answers = try FHIRPathExpression.evaluate(
            expression: "%resource.descendants().where(linkId = 'a').answer.value.where(code = 'yes')",
            context: Self.context()
        )
        #expect(answers.count == 1)
    }

    @Test
    func aMemberThatIsNotOneStringNeverMatches() throws {
        // A two-valued member is not equal to a single string, and neither is a number or a missing member.
        #expect(try Self.linkIds("%resource.item.where(linkId = 'c')").isEmpty)
        #expect(try Self.linkIds("%resource.item.where(linkId = '7')").isEmpty)
        #expect(try Self.linkIds("%resource.item.where(text = 'no linkId')").isEmpty, "matched, but carries no linkId to report")
        #expect(try FHIRPathExpression.evaluate(expression: "%resource.item.where(text = 'no linkId')", context: Self.context()).count == 1)
    }

    @Test
    func readsChoiceTypedMembersAndSkipsPrimitives() throws {
        // `value` reaches `valueCoding` on the coding answers; the string answer has no `code` and is skipped.
        let codes = try FHIRPathExpression.evaluate(
            expression: "%resource.descendants().where(linkId = 'a').answer.value.where(code = 'yes')",
            context: Self.context()
        )
        #expect(codes.count == 1)
        let topLevel = try FHIRPathExpression.evaluate(
            expression: "%resource.item.answer.value.where(code = 'yes')",
            context: Self.context()
        )
        #expect(topLevel.count == 1, "a's coding; its string answer and b's coding are not it")
    }
}
