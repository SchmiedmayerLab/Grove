//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Speech
import GroveSpeechRecognizer
import GroveSpeechSynthesizer
import SwiftUI

struct SpeechVoiceSelectionTestView: View {
   @Environment(SpeechSynthesizer.self) private var speechSynthesizer
   @State private var selectedVoiceIndex = 0
   @State private var message = ""

   var body: some View {
      VStack {
         TextField("Enter text to be spoken", text: $message)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()

          Picker("Voice", selection: $selectedVoiceIndex) {
              ForEach(speechSynthesizer.voices.indices, id: \.self) { index in
                  Text(speechSynthesizer.voices[index].name)
                      .tag(index)
              }
          }
              .pickerStyle(.inline)
              .accessibilityIdentifier("voicePicker")
              .padding()
          
         Button("Speak") {
            speechSynthesizer.speak(
                message,
                voice: speechSynthesizer.voices[selectedVoiceIndex]
            )
         }
      }
      .padding()
   }
}
