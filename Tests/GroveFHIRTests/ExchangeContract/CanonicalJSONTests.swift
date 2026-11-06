//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import Testing


/// `grove-canonical-json-v0`, beyond what the shared vectors pin.
@Suite
struct CanonicalJSONTests {
    private static func canonical(_ text: String) throws -> String {
        String(decoding: try LosslessJSONValue(parsing: Data(text.utf8)).canonicalBytes(), as: UTF8.self)
    }

    @Test("Members sort by the bytes of their names, at every depth")
    func memberOrder() throws {
        #expect(try Self.canonical(#"{"b":1,"a":{"z":1,"Z":2},"B":3,"_c":4,"aa":5}"#) == #"{"B":3,"_c":4,"a":{"Z":2,"z":1},"aa":5,"b":1}"#)
    }

    @Test("A member name with a scalar above U+007F is refused, raw or escaped")
    func nonASCIIMemberNames() {
        for text in [#"{"é":1}"#, #"{"\u00e9":1}"#, "{\"e\u{301}\":1}", #"{"a":{"\u212a":1}}"#] {
            #expect(throws: LosslessJSONValue.ParseError.nonASCIIMemberName, "\(text)") {
                try LosslessJSONValue(parsing: Data(text.utf8))
            }
        }
    }

    @Test("A repeated member name is refused, whatever its value and however it is spelled")
    func duplicateMembers() {
        for text in [#"{"a":1,"a":1}"#, #"{"a":1,"a":2}"#, #"{"a":1,"\u0061":2}"#] {
            #expect(throws: LosslessJSONValue.ParseError.duplicateMember, "\(text)") {
                try LosslessJSONValue(parsing: Data(text.utf8))
            }
        }
    }

    @Test("Canonically equivalent string values stay distinct content")
    func unnormalizedValues() throws {
        let precomposed = "{\"a\":\"\u{E9}\"}"
        let decomposed = "{\"a\":\"e\u{301}\"}"
        #expect(try LosslessJSONValue(parsing: Data(precomposed.utf8)) != LosslessJSONValue(parsing: Data(decomposed.utf8)))
        #expect(try Data(Self.canonical(precomposed).utf8) == Data(precomposed.utf8))
        #expect(try Data(Self.canonical(decomposed).utf8) == Data(decomposed.utf8))
    }

    @Test("Every string escape takes the RFC 8785 form, and the solidus stays raw")
    func stringEscapes() throws {
        #expect(try Self.canonical(#"["\"","\\","\/","\b","\f","\n","\r","\t"]"#) == #"["\"","\\","/","\b","\f","\n","\r","\t"]"#)
        #expect(try Self.canonical(#"["\u0000","\u001F","\u000b"]"#) == #"["\u0000","\u001f","\u000b"]"#)
        // U+007F, U+2028 and U+2029 are raw, whichever way the input spells them.
        #expect(try Self.canonical(#"["\u007F","\u2028","\u2029"]"#) == "[\"\u{7F}\",\"\u{2028}\",\"\u{2029}\"]")
        #expect(try Self.canonical(#"["\uD83D\uDE00","\uFEFF"]"#) == "[\"\u{1F600}\",\"\u{FEFF}\"]")
    }

    @Test("A number is its lexeme, verbatim")
    func numberLexemes() throws {
        let lexemes = "[72.0,72,-0,0.10,1E-7,1e2,1E+2,123456789012345678901234567890]"
        #expect(try Self.canonical(lexemes) == lexemes)
        #expect(try LosslessJSONValue(parsing: Data("72".utf8)) != LosslessJSONValue(parsing: Data("72.0".utf8)))
    }

    @Test("Literals, whitespace and nesting")
    func structure() throws {
        #expect(try Self.canonical(" {\t\"a\" : [ true , false , null , { } , [ ] ]\r\n} ") == #"{"a":[true,false,null,{},[]]}"#)
    }

    @Test("Canonicalizing canonical bytes changes nothing")
    func idempotence() throws {
        let canonical = try Self.canonical(#"{"b":[72.0,"\u00e9\/"],"a":{"c":"\t"}}"#)
        #expect(try Self.canonical(canonical) == canonical)
    }

    @Test("Every malformed text is refused for its reason")
    func refusals() {
        let refusals: [(String, LosslessJSONValue.ParseError)] = [
            (#"["\ud83d"]"#, .unpairedSurrogate),
            (#"["\ud83dx"]"#, .unpairedSurrogate),
            (#"["\ud83d\u0041"]"#, .unpairedSurrogate),
            (#"["\ude00"]"#, .unpairedSurrogate),
            (#"["\u+123"]"#, .invalidJSON),
            ("01", .invalidJSON),
            ("1.", .invalidJSON),
            ("NaN", .invalidJSON),
            ("Infinity", .invalidJSON),
            ("[1,]", .invalidJSON),
            ("{} {}", .invalidJSON),
            ("\"\n\"", .invalidJSON)
        ]
        for (text, reason) in refusals {
            #expect(throws: reason, "\(text)") {
                try LosslessJSONValue(parsing: Data(text.utf8))
            }
        }
    }
}
