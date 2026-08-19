//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFoundation
import Testing
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers


@Suite(.serialized)
final class FileManagerTests {
    private let fileManager = FileManager.default
    private let testRoot = URL.temporaryDirectory.appending(path: "GroveFoundationFileManagerTests", directoryHint: .isDirectory)
    
    init() throws {
        try? fileManager.removeItem(at: testRoot)
        try fileManager.createDirectory(at: testRoot, withIntermediateDirectories: false)
        print("\(Self.self) using testRoot: \(testRoot.path)")
    }
    
    @Test
    func doStuff() throws {
        #expect(try fileManager.contents(of: testRoot).isEmpty)
        let data = Data("HelloWorld".utf8)
        let fileUrl = testRoot.appendingPathComponent("file", conformingTo: .plainText)
        try data.write(to: fileUrl)
        #expect(try fileManager.contents(of: testRoot).mapIntoSet { $0.resolvingSymlinksInPath() } == [fileUrl])
        
        let folder1Url = testRoot.appending(path: "folder1", directoryHint: .isDirectory)
        let folder1File1Url = folder1Url.appendingPathComponent("file1", conformingTo: .plainText)
        #expect(!fileManager.itemExists(at: folder1Url))
        #expect(!fileManager.itemExists(at: folder1File1Url))
        #expect(!fileManager.isDirectory(at: folder1Url))
        #expect(throws: (any Error).self)  {
            try data.write(to: folder1File1Url)
        }
        try fileManager.prepareForWriting(to: folder1File1Url)
        try data.write(to: folder1File1Url)
        #expect(try fileManager.contents(of: testRoot).mapIntoSet { $0.resolvingSymlinksInPath() } == [fileUrl, folder1Url])
        #expect(try fileManager.contents(of: folder1Url).mapIntoSet(\.lastPathComponent) == ["file1.txt"])
        #expect(fileManager.itemExists(at: testRoot))
        #expect(fileManager.itemExists(at: fileUrl))
        #expect(fileManager.itemExists(at: folder1Url))
        #expect(fileManager.itemExists(at: folder1File1Url))
        #expect(fileManager.isDirectory(at: folder1Url))
        
        let folder2Url = testRoot.appending(path: "folder2", directoryHint: .isDirectory)
        try fileManager.copyItem(at: folder1Url, to: folder2Url, overwriteExisting: false)
        #expect(try fileManager.contents(of: testRoot).mapIntoSet { $0.resolvingSymlinksInPath() } == [fileUrl, folder1Url, folder2Url])
        do {
            let folder1Contents = try fileManager.contents(of: folder1Url).mapIntoSet(\.lastPathComponent)
            let folder2Contents = try fileManager.contents(of: folder2Url).mapIntoSet(\.lastPathComponent)
            #expect(folder1Contents == folder2Contents)
        }
        
        let folder1File2Url = folder1Url.appendingPathComponent("file2", conformingTo: .plainText)
        try data.write(to: folder1File2Url)
        #expect(try fileManager.contents(of: folder1Url).mapIntoSet(\.lastPathComponent) == ["file1.txt", "file2.txt"])
        
        #expect(throws: (any Error).self) {
            try self.fileManager.copyItem(at: folder1Url, to: folder2Url, overwriteExisting: false)
        }
        #expect(try fileManager.contents(of: folder2Url).mapIntoSet(\.lastPathComponent) == ["file1.txt"])
        try fileManager.copyItem(at: folder1Url, to: folder2Url, overwriteExisting: true)
        #expect(try fileManager.contents(of: folder2Url).mapIntoSet(\.lastPathComponent) == ["file1.txt", "file2.txt"])
    }
}
#endif
