//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

import Foundation


/// Encodes a value to the bytes `JSONEncoder` writes with `[.sortedKeys, .withoutEscapingSlashes]`, several times faster.
///
/// The output matches `JSONEncoder` byte for byte for everything a FHIR model encodes: members sorted by `String`
/// order, `Decimal` as its `description`, `URL` as its `absoluteString`, `Data` as Base64, integers and booleans as
/// written, and strings escaped only where JSON requires it (`"`, `\`, and the C0 controls, as `\b \t \n \f \r` or
/// `\u00xx`). A value it cannot reproduce exactly, a floating-point number or a `Date` among them, makes ``encode(_:)``
/// return `nil`, and the caller encodes with `JSONEncoder` instead.
enum WireJSONEncoder {
    fileprivate struct Unsupported: Error {}

    /// The wire bytes of `value`, or `nil` when they need `JSONEncoder`.
    static func encode<T: Encodable>(_ value: T) throws -> Data? {
        try encodeKeepingTree(value)?.json
    }

    /// The wire bytes of `value` and the JSON they state as native containers (`[String: Any]`, `[Any]`, `String`,
    /// `NSNumber`, `NSNull`), the shapes `JSONSerialization` parses them to; `nil` when the bytes need `JSONEncoder`.
    static func encodeKeepingTree<T: Encodable>(_ value: T) throws -> (json: Data, tree: Any)? {
        let node: Node
        do {
            node = try Node.encoding(value, parent: nil, key: nil)
        } catch is Unsupported {
            return nil
        }
        var writer = Writer()
        writer.write(node)
        return (Data(writer.bytes), node.nativeValue)
    }
}


// MARK: - Tree

extension WireJSONEncoder {
    fileprivate final class ObjectBox {
        var members: [(key: String, value: Node)] = []
    }

    fileprivate final class ArrayBox {
        var elements: [Node] = []
    }

    fileprivate enum Node {
        case object(ObjectBox)
        case array(ArrayBox)
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        /// The native value this node's bytes parse to; of members stated under one key, the last one stated.
        var nativeValue: Any {
            switch self {
            case .object(let box):
                var members = [String: Any](minimumCapacity: box.members.count)
                for (key, value) in box.members {
                    members[key] = value.nativeValue
                }
                return members
            case .array(let box):
                return box.elements.map(\.nativeValue)
            case .string(let string):
                return string
            case .number(let text):
                if let integer = Int64(text) {
                    return NSNumber(value: integer)
                }
                return NSNumber(value: Double(text) ?? .nan)
            case .bool(let value):
                return NSNumber(value: value)
            case .null:
                return NSNull()
            }
        }

        /// The node `value` encodes to, with the special cases `JSONEncoder` applies before calling `encode(to:)`.
        static func encoding<T: Encodable>(_ value: T, parent: Encoder?, key: CodingKey?) throws -> Node {
            if T.self == String.self {
                // swiftlint:disable:next force_cast
                return .string(value as! String)
            }
            if T.self == Decimal.self {
                // swiftlint:disable:next force_cast
                let decimal = value as! Decimal
                guard !decimal.isNaN else {
                    throw Unsupported()
                }
                return .number(decimal.description)
            }
            if T.self == URL.self {
                // swiftlint:disable:next force_cast
                return .string((value as! URL).absoluteString)
            }
            if T.self == Data.self {
                // swiftlint:disable:next force_cast
                return .string((value as! Data).base64EncodedString())
            }
            if T.self == Date.self || T.self == Double.self || T.self == Float.self {
                throw Unsupported()
            }
            let encoder = Encoder(parent: parent, key: key)
            try value.encode(to: encoder)
            guard let node = encoder.node else {
                // A nested value that encodes nothing is an empty object, as `JSONEncoder` writes it; at the top level,
                // `JSONEncoder` throws.
                guard parent != nil else {
                    throw Unsupported()
                }
                return .object(ObjectBox())
            }
            return node
        }
    }
}


// MARK: - Encoder

extension WireJSONEncoder {
    fileprivate final class Encoder: Swift.Encoder {
        let parent: Encoder?
        let key: CodingKey?
        var node: Node?

        var codingPath: [CodingKey] {
            var path: [CodingKey] = []
            var current: Encoder? = self
            while let encoder = current {
                if let key = encoder.key {
                    path.append(key)
                }
                current = encoder.parent
            }
            return path.reversed()
        }

        var userInfo: [CodingUserInfoKey: Any] { [:] }

        init(parent: Encoder?, key: CodingKey?) {
            self.parent = parent
            self.key = key
        }

        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            KeyedEncodingContainer(KeyedContainer<Key>(encoder: self, box: objectBox()))
        }

        func unkeyedContainer() -> UnkeyedEncodingContainer {
            UnkeyedContainer(encoder: self, box: arrayBox())
        }

        func singleValueContainer() -> SingleValueEncodingContainer {
            SingleValueContainer(encoder: self)
        }

        /// The object this encoder writes into, shared by every keyed container it hands out, as a subclass and its
        /// superclass both encode into one object.
        func objectBox() -> ObjectBox {
            if case .object(let box)? = node {
                return box
            }
            let box = ObjectBox()
            node = .object(box)
            return box
        }

        func arrayBox() -> ArrayBox {
            if case .array(let box)? = node {
                return box
            }
            let box = ArrayBox()
            node = .array(box)
            return box
        }
    }

    fileprivate struct IndexKey: CodingKey {
        let intValue: Int?
        var stringValue: String { "Index \(intValue ?? 0)" }

        init(intValue: Int) {
            self.intValue = intValue
        }

        init?(stringValue: String) {
            nil
        }
    }

    fileprivate struct SuperKey: CodingKey {
        var stringValue: String { "super" }
        var intValue: Int? { nil }

        init() {}

        init?(stringValue: String) {
            nil
        }

        init?(intValue: Int) {
            nil
        }
    }

    fileprivate struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoder: Encoder
        let box: ObjectBox

        var codingPath: [CodingKey] { encoder.codingPath }

        private func set(_ node: Node, for key: Key) {
            box.members.append((key.stringValue, node))
        }

        mutating func encodeNil(forKey key: Key) throws {
            set(.null, for: key)
        }

        mutating func encode(_ value: Bool, forKey key: Key) throws {
            set(.bool(value), for: key)
        }

        mutating func encode(_ value: String, forKey key: Key) throws {
            set(.string(value), for: key)
        }

        mutating func encode(_ value: Double, forKey key: Key) throws {
            throw Unsupported()
        }

        mutating func encode(_ value: Float, forKey key: Key) throws {
            throw Unsupported()
        }

        mutating func encode(_ value: Int, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: Int8, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: Int16, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: Int32, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: Int64, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: UInt, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: UInt8, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: UInt16, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: UInt32, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode(_ value: UInt64, forKey key: Key) throws {
            set(.number(String(value)), for: key)
        }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            set(try Node.encoding(value, parent: encoder, key: key), for: key)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy keyType: NestedKey.Type,
            forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            let nested = Encoder(parent: encoder, key: key)
            let nestedBox = nested.objectBox()
            set(.object(nestedBox), for: key)
            return KeyedEncodingContainer(KeyedContainer<NestedKey>(encoder: nested, box: nestedBox))
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            let nested = Encoder(parent: encoder, key: key)
            let nestedBox = nested.arrayBox()
            set(.array(nestedBox), for: key)
            return UnkeyedContainer(encoder: nested, box: nestedBox)
        }

        mutating func superEncoder() -> Swift.Encoder {
            superEncoder(forKey: SuperKey())
        }

        mutating func superEncoder(forKey key: Key) -> Swift.Encoder {
            superEncoder(forKey: key as CodingKey)
        }

        private func superEncoder(forKey key: CodingKey) -> Swift.Encoder {
            let nested = Encoder(parent: encoder, key: key)
            box.members.append((key.stringValue, .object(nested.objectBox())))
            return nested
        }
    }

    fileprivate struct UnkeyedContainer: UnkeyedEncodingContainer {
        let encoder: Encoder
        let box: ArrayBox

        var codingPath: [CodingKey] { encoder.codingPath }
        var count: Int { box.elements.count }

        mutating func encodeNil() throws {
            box.elements.append(.null)
        }

        mutating func encode(_ value: Bool) throws {
            box.elements.append(.bool(value))
        }

        mutating func encode(_ value: String) throws {
            box.elements.append(.string(value))
        }

        mutating func encode(_ value: Double) throws {
            throw Unsupported()
        }

        mutating func encode(_ value: Float) throws {
            throw Unsupported()
        }

        mutating func encode(_ value: Int) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: Int8) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: Int16) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: Int32) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: Int64) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: UInt) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: UInt8) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: UInt16) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: UInt32) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode(_ value: UInt64) throws {
            box.elements.append(.number(String(value)))
        }

        mutating func encode<T: Encodable>(_ value: T) throws {
            box.elements.append(try Node.encoding(value, parent: encoder, key: IndexKey(intValue: box.elements.count)))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            let nested = Encoder(parent: encoder, key: IndexKey(intValue: box.elements.count))
            let nestedBox = nested.objectBox()
            box.elements.append(.object(nestedBox))
            return KeyedEncodingContainer(KeyedContainer<NestedKey>(encoder: nested, box: nestedBox))
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            let nested = Encoder(parent: encoder, key: IndexKey(intValue: box.elements.count))
            let nestedBox = nested.arrayBox()
            box.elements.append(.array(nestedBox))
            return UnkeyedContainer(encoder: nested, box: nestedBox)
        }

        mutating func superEncoder() -> Swift.Encoder {
            let nested = Encoder(parent: encoder, key: IndexKey(intValue: box.elements.count))
            box.elements.append(.object(nested.objectBox()))
            return nested
        }
    }

    fileprivate struct SingleValueContainer: SingleValueEncodingContainer {
        let encoder: Encoder

        var codingPath: [CodingKey] { encoder.codingPath }

        mutating func encodeNil() throws {
            encoder.node = .null
        }

        mutating func encode(_ value: Bool) throws {
            encoder.node = .bool(value)
        }

        mutating func encode(_ value: String) throws {
            encoder.node = .string(value)
        }

        mutating func encode(_ value: Double) throws {
            throw Unsupported()
        }

        mutating func encode(_ value: Float) throws {
            throw Unsupported()
        }

        mutating func encode(_ value: Int) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: Int8) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: Int16) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: Int32) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: Int64) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: UInt) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: UInt8) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: UInt16) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: UInt32) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode(_ value: UInt64) throws {
            encoder.node = .number(String(value))
        }

        mutating func encode<T: Encodable>(_ value: T) throws {
            encoder.node = try Node.encoding(value, parent: encoder.parent, key: encoder.key)
        }
    }
}


// MARK: - Writer

extension WireJSONEncoder {
    fileprivate struct Writer {
        private static let hexDigits = Array("0123456789abcdef".utf8)

        private(set) var bytes: [UInt8] = []

        init() {
            bytes.reserveCapacity(16_384)
        }

        mutating func write(_ node: Node) {
            switch node {
            case .object(let box):
                writeObject(box)
            case .array(let box):
                bytes.append(UInt8(ascii: "["))
                for (index, element) in box.elements.enumerated() {
                    if index > 0 {
                        bytes.append(UInt8(ascii: ","))
                    }
                    write(element)
                }
                bytes.append(UInt8(ascii: "]"))
            case .string(let string):
                writeString(string)
            case .number(let text):
                bytes.append(contentsOf: text.utf8)
            case .bool(let value):
                bytes.append(contentsOf: value ? Array("true".utf8) : Array("false".utf8))
            case .null:
                bytes.append(contentsOf: "null".utf8)
            }
        }

        /// Members in `String` order; of members stated under one key, the last one stated, as a dictionary keeps it.
        private mutating func writeObject(_ box: ObjectBox) {
            let members = box.members
            let order = members.indices.sorted { lhs, rhs in
                members[lhs].key != members[rhs].key ? members[lhs].key < members[rhs].key : lhs < rhs
            }
            bytes.append(UInt8(ascii: "{"))
            var isFirst = true
            for (position, index) in order.enumerated() {
                if position + 1 < order.count, members[order[position + 1]].key == members[index].key {
                    continue
                }
                if !isFirst {
                    bytes.append(UInt8(ascii: ","))
                }
                isFirst = false
                writeString(members[index].key)
                bytes.append(UInt8(ascii: ":"))
                write(members[index].value)
            }
            bytes.append(UInt8(ascii: "}"))
        }

        private mutating func writeString(_ string: String) {
            bytes.append(UInt8(ascii: "\""))
            var string = string
            string.withUTF8 { utf8 in
                var runStart = 0
                for (index, byte) in utf8.enumerated() where byte < 0x20 || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "\\") {
                    bytes.append(contentsOf: UnsafeBufferPointer(rebasing: utf8[runStart..<index]))
                    runStart = index + 1
                    bytes.append(UInt8(ascii: "\\"))
                    switch byte {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"):
                        bytes.append(byte)
                    case 0x08:
                        bytes.append(UInt8(ascii: "b"))
                    case 0x09:
                        bytes.append(UInt8(ascii: "t"))
                    case 0x0A:
                        bytes.append(UInt8(ascii: "n"))
                    case 0x0C:
                        bytes.append(UInt8(ascii: "f"))
                    case 0x0D:
                        bytes.append(UInt8(ascii: "r"))
                    default:
                        bytes.append(contentsOf: [UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0")])
                        bytes.append(Self.hexDigits[Int(byte >> 4)])
                        bytes.append(Self.hexDigits[Int(byte & 0x0F)])
                    }
                }
                bytes.append(contentsOf: UnsafeBufferPointer(rebasing: utf8[runStart...]))
            }
            bytes.append(UInt8(ascii: "\""))
        }
    }
}
