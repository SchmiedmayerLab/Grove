//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// The `FirebaseStorageTests` require the Firebase Storage Emulator to run at port 9199.
///
/// Refer to https://firebase.google.com/docs/emulator-suite#storage about more information about the
/// Firebase Local Emulator Suite.
final class FirebaseStorageTests: XCTestCase {
    struct FirebaseStorageItem: Decodable {
        let name: String
        let bucket: String
    }
    
   
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false

        try await Self.deleteAllFiles()
        try await Self.waitForFileCount(0)
    }

    @MainActor
    func testFirebaseStorageFileUpload() async throws {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseStorage"]), "The app did not come up.")
        app.buttons["FirebaseStorage"].tap()

        let documents = try await Self.getAllFiles()
        XCTAssert(documents.isEmpty)

        XCTAssert(app.buttons["Upload"].wait(for: \.isHittable, toEqual: true, timeout: 10.0))
        app.buttons["Upload"].tap()

        try await Self.waitForFileCount(1)
    }
}


extension FirebaseStorageTests {
    private static func getAllFiles() async throws -> [FirebaseStorageItem] {
        let documentsURL = try XCTUnwrap(
            URL(string: "http://localhost:9199/v0/b/STORAGE_BUCKET/o")
        )
        let (data, response) = try await URLSession.shared.data(from: documentsURL)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirebaseStorageTests` require the Firebase Storage Emulator to run at port 9199.
                
                Refer to https://firebase.google.com/docs/emulator-suite#storage about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }

        struct ResponseWrapper: Decodable {
            let items: [FirebaseStorageItem]
        }

        do {
            return try JSONDecoder().decode(ResponseWrapper.self, from: data).items
        } catch {
            return []
        }
    }

    /// Polls the emulator until it holds `expected` files and asserts the result, so the test observes the upload instead of sleeping for it.
    private static func waitForFileCount(
        _ expected: Int,
        timeout: Duration = .seconds(10),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        var count = try await getAllFiles().count

        while count != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            count = try await getAllFiles().count
        }

        XCTAssertEqual(count, expected, file: file, line: line)
    }

    private static func deleteAllFiles() async throws {
        for storageItem in try await getAllFiles() {
            let url = try XCTUnwrap(
                URL(string: "http://localhost:9199/v0/b/STORAGE_BUCKET/o/\(storageItem.name)")
            )
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let urlResponse = response as? HTTPURLResponse,
                  200...299 ~= urlResponse.statusCode else {
                print(
                    """
                    The `FirebaseStorageTests` require the Firebase Storage Emulator to run at port 9199.
                    
                    Refer to https://firebase.google.com/docs/emulator-suite#storage about more information about the
                    Firebase Local Emulator Suite.
                    """
                )
                throw URLError(.fileDoesNotExist)
            }
        }
    }
}
