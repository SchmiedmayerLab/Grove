//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import Testing


@Suite
struct CompressionAlgorithmTests {
    private let longInput: Data
    
    init() throws {
        var longText = ""
        for _ in 0..<40_000 {
            longText.append(try #require(Self.textSnippets.randomElement()))
        }
        self.longInput = try #require(longText.data(using: .utf8))
    }
    
    @Test
    func zlib() throws {
        let input = try #require(String(repeating: "Hello Grove :)", count: 1000).data(using: .utf8))
        #expect(input.count == 14_000)
        let compressed = try input.compressed(using: Zlib.self, options: .init(level: .bestCompression))
        #expect(compressed.count == 69)
        #expect(compressed == Data([
            120, 218, 237, 199, 49, 13, 0, 32, 12, 0, 48, 43, 123, 177, 128, 1, 102, 100,
            31, 201, 18, 14, 244, 227, 129, 187, 253, 154, 181, 119, 199, 58, 125, 43, 230, 72,
            51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
            51, 51, 51, 51, 51, 51, 51, 51, 179, 175, 61, 219, 145, 250, 144
        ]))
        let decompressed = try compressed.decompressed(using: Zlib.self)
        #expect(decompressed == input)
    }
    
    @Test
    func zlibHmmm() throws {
        let input = longInput
        let compressed1 = try input.compressed(using: Zlib.self, options: .init(level: .bestSpeed))
        let compressed2 = try input.compressed(using: Zlib.self, options: .init(level: .bestCompression))
        print(input.count, compressed1.count, compressed2.count)
        #expect(try compressed1.decompressed(using: Zlib.self).elementsEqual(input))
        #expect(try compressed2.decompressed(using: Zlib.self).elementsEqual(input))
    }
    
    @Test
    func zlibCompressionOptions() throws {
        let input = longInput
        let compressed1 = try input.compressed(using: Zlib.self, options: .init(level: .bestSpeed))
        let compressed2 = try input.compressed(using: Zlib.self, options: .init(level: .bestCompression))
        #expect(compressed1.count > compressed2.count)
        print(input.count, compressed1.count, compressed2.count)
        #expect(try compressed1.decompressed(using: Zlib.self).elementsEqual(input))
        #expect(try compressed2.decompressed(using: Zlib.self).elementsEqual(input))
    }
    
    
    @Test
    func zstd() throws {
        let input = try #require(String(repeating: "Hello Grove :)", count: 1000).data(using: .utf8))
        #expect(input.count == 14_000)
        let compressed = try input.compressed(using: Zstd.self)
        print(Array(compressed))
        #expect(compressed.count == 32)
        #expect(compressed == Data([
            40, 181, 47, 253, 96, 176, 53, 181, 0, 0, 112, 72, 101, 108, 108, 111,
            32, 71, 114, 111, 118, 101, 32, 58, 41, 1, 0, 159, 54, 248, 169, 4
        ]))
        let decompressed = try compressed.decompressed(using: Zstd.self)
        #expect((decompressed == input) as Bool)
    }
    
    @Test
    func zstdCompressionOptions() throws {
        let input = longInput
        let compressed1 = try input.compressed(using: Zstd.self, options: .init(level: .minRegular))
        let compressed2 = try input.compressed(using: Zstd.self, options: .init(level: .maxRegular))
        #expect(compressed1.count > compressed2.count)
        print(input.count, compressed1.count, compressed2.count)
        #expect(try compressed1.decompressed(using: Zstd.self).elementsEqual(input))
        #expect(try compressed2.decompressed(using: Zstd.self).elementsEqual(input))
    }
}


// swiftlint:disable line_length

extension CompressionAlgorithmTests {
    private static let textSnippets: [String] = [
        """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        """,
        """
        Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur?
        """,
        """
        But I must explain to you how all this mistaken idea of denouncing pleasure and praising pain was born and I will give you a complete account of the system, and expound the actual teachings of the great explorer of the truth, the master-builder of human happiness. No one rejects, dislikes, or avoids pleasure itself, because it is pleasure, but because those who do not know how to pursue pleasure rationally encounter consequences that are extremely painful. Nor again is there anyone who loves or pursues or desires to obtain pain of itself, because it is pain, but because occasionally circumstances occur in which toil and pain can procure him some great pleasure. To take a trivial example, which of us ever undertakes laborious physical exercise, except to obtain some advantage from it? But who has any right to find fault with a man who chooses to enjoy a pleasure that has no annoying consequences, or one who avoids a pain that produces no resultant pleasure?
        """,
        """
        At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident, similique sunt in culpa qui officia deserunt mollitia animi, id est laborum et dolorum fuga. Et harum quidem rerum facilis est et expedita distinctio. Nam libero tempore, cum soluta nobis est eligendi optio cumque nihil impedit quo minus id quod maxime placeat facere possimus, omnis voluptas assumenda est, omnis dolor repellendus. Temporibus autem quibusdam et aut officiis debitis aut rerum necessitatibus saepe eveniet ut et voluptates repudiandae sint et molestiae non recusandae. Itaque earum rerum hic tenetur a sapiente delectus, ut aut reiciendis voluptatibus maiores alias consequatur aut perferendis doloribus asperiores repellat.
        """,
        """
        On the other hand, we denounce with righteous indignation and dislike men who are so beguiled and demoralized by the charms of pleasure of the moment, so blinded by desire, that they cannot foresee the pain and trouble that are bound to ensue; and equal blame belongs to those who fail in their duty through weakness of will, which is the same as saying through shrinking from toil and pain. These cases are perfectly simple and easy to distinguish. In a free hour, when our power of choice is untrammelled and when nothing prevents our being able to do what we like best, every pleasure is to be welcomed and every pain avoided. But in certain circumstances and owing to the claims of duty or the obligations of business it will frequently occur that pleasures have to be repudiated and annoyances accepted. The wise man therefore always holds in these matters to this principle of selection: he rejects pleasures to secure other greater pleasures, or else he endures pains to avoid worse pains.
        """
    ]
}
