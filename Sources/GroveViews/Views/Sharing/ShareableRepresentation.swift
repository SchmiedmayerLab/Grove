//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog
#if !os(watchOS)
import PDFKit
#endif
import UniformTypeIdentifiers


final class ShareableRepresentation: NSObject {
    private static let logger = Logger(subsystem: "org.grovealliance.views", category: "UI")
    
    private let value: Any
    private let cleanupHandler: () throws -> Void
    
    private init(value: Any, cleanupHandler: @escaping @Sendable () throws -> Void = {}) {
        self.value = value
        self.cleanupHandler = cleanupHandler
        super.init()
    }
    
    #if !os(watchOS)
    @available(iOS 18, macOS 15, watchOS 11, *)
    convenience init(pdf: PDFKit.PDFDocument) {
        let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "file"
        let url = Self.tmpUrl(for: title, conformingTo: .pdf)
        if let data = pdf.dataRepresentation(), (try? data.write(to: url)) != nil {
            // success
        } else {
            Self.logger.error("Failed to write PDF to disk")
        }
        self.init(value: url) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    #endif
    
    deinit {
        do {
            try cleanupHandler()
        } catch {
            Self.logger.error("Error in cleanup handler: \(error)")
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ShareableRepresentation {
    private static func tmpUrl(for filename: String, conformingTo type: UTType) -> URL {
        let fileManager = FileManager.default
        let baseUrl = fileManager.temporaryDirectory.appending(component: "GroveShareSheet", directoryHint: .isDirectory)
        let fileUrl = baseUrl.appendingPathComponent(filename, conformingTo: type)
        try? fileManager.createDirectory(at: baseUrl, withIntermediateDirectories: true)
        return fileUrl
    }
}


extension ShareableRepresentation: NSItemProviderWriting {
    static var writableTypeIdentifiersForItemProvider: [String] {
        []
    }
    
    var writableTypeIdentifiersForItemProvider: [String] {
        if let value = value as? any NSItemProviderWriting {
            return value.writableTypeIdentifiersForItemProvider ?? type(of: value).writableTypeIdentifiersForItemProvider
        } else {
            Self.logger.error("Value of type '\(type(of: self.value))' doesn't conform to \((any NSItemProviderWriting).self)!")
            return []
        }
    }
    
    func loadData(
        withTypeIdentifier typeIdentifier: String,
        forItemProviderCompletionHandler completionHandler: @escaping @Sendable (Data?, (any Error)?) -> Void
    ) -> Progress? {
        if let value = value as? any NSItemProviderWriting {
            return value.loadData(withTypeIdentifier: typeIdentifier, forItemProviderCompletionHandler: completionHandler)
        } else {
            Self.logger.error("Value of type '\(type(of: self.value))' doesn't conform to \((any NSItemProviderWriting).self)!")
            completionHandler(nil, NSError(domain: "org.grovealliance.views", code: 0))
            return nil
        }
    }
}
