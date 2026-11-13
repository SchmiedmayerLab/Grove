//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


struct SimpleMarkdownViewTest: View {
    @State private var viewState: ViewState = .idle
    @State private var textAlignment: TextAlignment = .center
    
    var body: some View {
        ScrollView {
            Group {
                asyncMarkdownView
                dataMarkdownView
            }
            .multilineTextAlignment(textAlignment)
            .padding(.horizontal)
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .bottomBar) {
                toolbarContent
            }
            #elseif os(macOS)
            ToolbarItem(placement: .status) {
                toolbarContent
            }
            #else
            ToolbarItem(placement: .automatic) {
                toolbarContent
            }
            #endif
        }
    }


    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers MarkdownView's deprecated `Data` initializers.")
    #endif
    private var asyncMarkdownView: some View {
        MarkdownView(
            asyncMarkdown: {
                try? await Task.sleep(for: .seconds(2))
                return Data("This is a *markdown* **example** taking 2 seconds to load.".utf8)
            }
        )
    }

    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers MarkdownView's deprecated `Data` initializers.")
    #endif
    private var dataMarkdownView: some View {
        MarkdownView(
            markdown: Data("This is a *markdown* **example**.".utf8)
        )
    }


    private var toolbarContent: some View {
        HStack {
            Text("Text Alignment")
            Spacer()
            Picker("", selection: $textAlignment) {
                ForEach(TextAlignment.allCases, id: \.self) { alignment in
                    Text(alignment.debugName)
                }
            }
            .pickerStyle(.menu)
        }
    }
}


extension TextAlignment {
    var debugName: String {
        switch self {
        case .leading:
            "leading"
        case .trailing:
            "trailing"
        case .center:
            "center"
        }
    }
}


#if DEBUG
#Preview {
    SimpleMarkdownViewTest()
}
#endif
