//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
#if canImport(UniformTypeIdentifiers)
public import UniformTypeIdentifiers
#endif


/// An IANA media type, as FHIR carries one in `Attachment.contentType` and the SDC `mimeType` extension.
///
/// The string is the contract: FHIR states a media type and Grove stores exactly what it was given, so a
/// type the platform has never heard of survives a round trip. Apple platforms map to and from `UTType`
/// where they need to, which is a lookup that can fail — the media type stays authoritative.
public struct MIMEType: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public var description: String {
        rawValue
    }

    /// The type before the `/`, e.g. `image` in `image/png`.
    public var type: String {
        String(rawValue.prefix { $0 != "/" })
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}


extension MIMEType: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}


extension MIMEType {
    // swiftlint:disable missing_docs
    public static let png: Self = "image/png"
    public static let jpeg: Self = "image/jpeg"
    public static let pdf: Self = "application/pdf"
    public static let plainText: Self = "text/plain"
    // swiftlint:enable missing_docs

    /// What `Attachment.contentType` falls back to when nothing better is known (RFC 2046).
    public static let octetStream: Self = "application/octet-stream"
}


#if canImport(UniformTypeIdentifiers)
extension MIMEType {
    /// The platform's type for this media type, if it knows one.
    public var utType: UTType? {
        UTType(mimeType: rawValue)
    }

    /// The media type the platform prefers for a `UTType`, if it declares one.
    public init?(_ utType: UTType) {
        guard let preferred = utType.preferredMIMEType else {
            return nil
        }
        self.init(rawValue: preferred)
    }
}
#endif
