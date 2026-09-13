//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveChat
import SwiftUI


/// The conversation the documentation screenshots show: a lab letter the participant photographed, its two flagged
/// values explained, and a picture the assistant draws of what brings one of them down.
///
/// Launched with `--documentation`. The photo and the drawing are pictures in the app's resources, generated once;
/// the conversation itself is written here.
@MainActor
enum DocumentationConversation {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--documentation")
    }

    static let title = "Health Assistant"

    static var chat: Chat {
        [
            ChatEntity(
                role: .user,
                content: .images([.image(picture("LabReport"))], text: "My doctor's office mailed me these results and flagged two of them. What do they mean?")
            ),
            ChatEntity(role: .assistant(.response), text: """
                Three values are flagged, with two stories behind them:

                - **LDL cholesterol, 162 mg/dL**, which is also why your total cholesterol of 242 is high. On the usual scale LDL counts as high from 160; under 100 is optimal. It is the part of cholesterol that settles in artery walls over the years, and how much it matters depends on your overall risk, which takes in age, blood pressure, smoking, diabetes and family history, not the number alone.
                - **HbA1c, 5.9 %.** This is inside the 5.7 to 6.4 band that counts as prediabetes: an average blood sugar over the past three months that is above normal but below the diabetes threshold of 6.5.

                Your HDL of 52 and triglycerides of 140 are within their usual ranges.

                Both flags are common, and both respond to the same changes: more fibre and unsaturated fats, less saturated fat and sugar, regular activity, and weight where that applies. Whether medication is worth it is a risk decision for you and your doctor; a lab value alone does not settle it. Bring the letter to your next visit.

                I am the study's assistant, not a clinician: this explains the report, it does not replace the conversation about it.
                """),
            ChatEntity(role: .user, text: "Can you draw me a simple picture of what brings LDL down? Something for the fridge.")
        ]
    }

    /// A worded answer with the places it came from, for a question about the first item on the list.
    static var citedAnswer: ChatEntity {
        ChatEntity(
            role: .assistant(.response),
            content: .text("Oats carry beta-glucan, a soluble fibre that forms a gel in the gut and binds bile acids, so the liver draws on its cholesterol to make more. About 3 g a day, a large bowl of porridge, lowers LDL by roughly 5 to 7 percent on its own, which is why it comes first on the list. Beans, barley and psyllium work the same way."),
            citations: [
                .init(title: "Cholesterol: Top foods to improve your numbers — Mayo Clinic", source: .web(URL(string: "https://www.mayoclinic.org/diseases-conditions/high-blood-cholesterol/in-depth/cholesterol/art-20045192")!)),
                .init(title: "Cholesterol-lowering effects of oat β-glucan: a meta-analysis of randomized controlled trials — Whitehead et al., 2014", source: .web(URL(string: "https://doi.org/10.3945/ajcn.114.086108")!)),
                .init(title: "Participant Information Sheet.pdf", source: .file(name: "Participant Information Sheet.pdf"))
            ]
        )
    }

    /// The assistant reading the participant's earlier results through a tool before answering.
    static let toolCall = ChatEntity(role: .assistant(.toolCall), text: "read_health_records({ \"type\": \"labResult\", \"code\": \"LOINC 13457-7\", \"limit\": 2 })")
    static let toolResponse = ChatEntity(role: .assistant(.toolResponse), text: "{ \"results\": [ { \"date\": \"2026-09-08\", \"value\": 162, \"unit\": \"mg/dL\" }, { \"date\": \"2025-03-14\", \"value\": 148, \"unit\": \"mg/dL\" } ] }")
    static let toolAnswer = ChatEntity(role: .assistant(.response), text: "Your previous LDL, from March 2025, was **148 mg/dL**. This one is 14 higher, so the direction is up as well as the level.")

    /// What the assistant draws in answer to the last message.
    static var drawing: ChatEntity.Content {
        .images(
            [.image(picture("Illustration"))],
            text: "Oats and beans, nuts, olive oil, fish, vegetables and fruit, and a daily walk. Less butter, fatty meat and pastry does the rest."
        )
    }

    /// A picture from the app's resources; a missing one shows as a flat tile, so the walk still runs.
    private static func picture(_ name: String) -> PlatformImage {
        if let image = PlatformImage(named: name) {
            return image
        }
        let renderer = ImageRenderer(content: Color.gray.opacity(0.3).frame(width: 1024, height: 1024))
        renderer.scale = 1
        return renderer.uiImage ?? PlatformImage()
    }
}
