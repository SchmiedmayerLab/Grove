//
// This source file is part of the Stanford Spezi open source project ,
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


func routes(_ app: Application) throws {
    app.get("users") { req async throws -> [UserData] in
        let dataModule = req.spezi[TestModule.self]
        return dataModule.getAllUsers()
    }
    
    app.get("users", ":id") { req async throws -> UserData in
        let dataModule = req.spezi[TestModule.self]
        guard let idString = req.parameters.get("id"),
              let id = Int(idString),
              let user = dataModule.getUser(byId: id) else {
            throw Abort(.notFound)
        }
        return user
    }
}
