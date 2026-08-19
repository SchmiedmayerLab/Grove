//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveKeychainStorage
import SwiftUI
import XCTestApp


struct KeychainStorageTestsView: View {
    @Environment(KeychainStorage.self) var keychainStorage
    
    var body: some View {
        TestAppView(testCase: KeychainStorageTests(keychainStorage: keychainStorage))
    }
}
