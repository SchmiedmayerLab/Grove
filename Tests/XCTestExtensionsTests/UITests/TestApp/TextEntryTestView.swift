//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct TextEntryTestView: View {
    @State var text = ""
    @State var secureText = ""
    @State var accidentalPress = false
    
    var body: some View {
        Form {
            Section("Accidental Buttons") {
                // we are testing that our keyboard logic doesn't accidentally tap buttons it shouldn't tap
                Button("Done", action: accidentalAction)
                Button("Continue", action: accidentalAction)
                Button("Return", action: accidentalAction)
                if accidentalPress {
                    Text("Button was pressed!")
                        .foregroundColor(.red)
                }
            }
            Section {
                TextField("TextField", text: $text, prompt: Text("TextField"))
                Text(text.isEmpty ? "No text set ..." : text)
            }
            .submitLabel(.continue)
            Section {
                SecureField("SecureField", text: $secureText, prompt: Text("SecureField"))
                Text(secureText.isEmpty ? "No secure text set ..." : secureText)
            }
        }
    }

    func accidentalAction() {
        accidentalPress = true
    }
}
