//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI

/// A view that displays the results of a ``ValidationEngine``.
///
/// For more information on the content this view displays, refer to ``FailedValidationResult``.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ValidationResultsView: View {
    private let results: [FailedValidationResult]

    public var body: some View {
        VStack(alignment: .leading) {
            ForEach(results) { result in
                Text(result.message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
            .font(.footnote)
            .foregroundColor(.red)
    }

    /// Create a new view.
    /// - Parameter results: The array of ``FailedValidationResult`` coming from the ``ValidationEngine``.
    public init(results: [FailedValidationResult]) {
        self.results = results
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    ValidationResultsView(results: [
        .init(from: .nonEmpty),
        .init(from: .mediumPassword)
    ])
}
#endif
