//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Charts
import GroveChat
import SwiftUI


/// The conversation the documentation screenshots show: a resting heart rate that crept up, read from a chart the
/// user attached, answered with a chart the assistant drew.
///
/// Launched with `--documentation`; the pictures are rendered here rather than shipped as assets.
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
                content: .images([.image(heartRateChart())], text: "My resting heart rate has been creeping up this month. Here's what my watch shows.")
            ),
            ChatEntity(role: .assistant(.response), text: """
                Your resting heart rate averaged **64 bpm** this month, up from 58 in the first week.

                A few things stand out:
                - The highest readings follow the days with almost no walking.
                - It settles again on days with a walk after dinner.

                Twenty minutes of walking a day would likely bring it back down within a few weeks.
                """),
            ChatEntity(role: .user, text: "Can you sketch a walking plan for the next two weeks?")
        ]
    }

    /// A worded answer with the places it came from, for a question about the numbers.
    static var citedAnswer: ChatEntity {
        ChatEntity(
            role: .assistant(.response),
            content: .text("A resting heart rate in the 60s is within the normal range for adults. What matters more than the number is the trend: a steady rise over weeks is worth mentioning at your next visit."),
            citations: [
                .init(title: "Target Heart Rates Chart — American Heart Association", source: .web(URL(string: "https://www.heart.org/en/healthy-living/fitness/fitness-basics/target-heart-rates")!)),
                .init(title: "Resting heart rate — Mayo Clinic", source: .web(URL(string: "https://www.mayoclinic.org/healthy-lifestyle/fitness/expert-answers/heart-rate/faq-20057979")!)),
                .init(title: "Study Handbook.pdf", source: .file(name: "Study Handbook.pdf"))
            ]
        )
    }

    /// The assistant reading the watch's data through a tool before answering.
    static let toolCall = ChatEntity(role: .assistant(.toolCall), text: "read_health_samples({ type: \"restingHeartRate\", days: 30 })")
    static let toolResponse = ChatEntity(role: .assistant(.toolResponse), text: "{ samples: 30, average: 64, minimum: 58, maximum: 68 }")
    static let toolAnswer = ChatEntity(role: .assistant(.response), text: "Over the last 30 days your resting heart rate averaged **64 bpm**, ranging from 58 to 68.")

    /// What the assistant draws in answer to the last message.
    static var drawing: ChatEntity.Content {
        .images([.image(walkingPlanChart())], text: "Here's a plan that builds up gently: ten minutes a day in the first week, twenty in the second, with two rest days each week.")
    }

    /// Resting heart rate over the last month, the way a watch app would chart it.
    private static func heartRateChart() -> PlatformImage {
        let readings: [(day: Int, bpm: Double)] = [
            (1, 58), (3, 59), (5, 58), (7, 60), (9, 61), (11, 60), (13, 63), (15, 62), (17, 64), (19, 66), (21, 65), (23, 67), (25, 66), (27, 68), (29, 67)
        ]
        return render {
            VStack(alignment: .leading, spacing: 12) {
                Text("Resting Heart Rate")
                    .font(.title2.bold())
                Text("Last 30 days · avg 64 bpm")
                    .foregroundStyle(.secondary)
                Chart(readings, id: \.day) { reading in
                    LineMark(x: .value("Day", reading.day), y: .value("bpm", reading.bpm))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.red.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 4))
                    PointMark(x: .value("Day", reading.day), y: .value("bpm", reading.bpm))
                        .foregroundStyle(.red)
                }
                .chartYScale(domain: 50...75)
                .chartXAxis {
                    AxisMarks(values: [1, 8, 15, 22, 29]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let day = value.as(Int.self) {
                                Text("Day \(day)")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [50, 60, 70]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bpm = value.as(Int.self) {
                                Text("\(bpm) bpm")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The two weeks the assistant proposes, as minutes of walking per day.
    private static func walkingPlanChart() -> PlatformImage {
        struct Walk {
            let day: String
            let week: String
            let minutes: Double
        }
        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let firstWeek: [Double] = [10, 10, 0, 10, 10, 15, 0]
        let secondWeek: [Double] = [20, 20, 0, 20, 20, 25, 0]
        let days = zip(weekdays, firstWeek).map { Walk(day: $0, week: "Week 1", minutes: $1) }
            + zip(weekdays, secondWeek).map { Walk(day: $0, week: "Week 2", minutes: $1) }
        return render {
            VStack(alignment: .leading, spacing: 12) {
                Text("Walking Plan")
                    .font(.title2.bold())
                Text("Minutes per day, next two weeks")
                    .foregroundStyle(.secondary)
                Chart(Array(days.enumerated()), id: \.offset) { _, entry in
                    BarMark(x: .value("Day", entry.day), y: .value("Minutes", entry.minutes))
                        .foregroundStyle(entry.week == "Week 1" ? Color.teal.gradient : Color.indigo.gradient)
                        .position(by: .value("Week", entry.week))
                        .cornerRadius(5)
                }
                .chartYScale(domain: 0...30)
                .chartLegend(position: .top, alignment: .leading)
                .chartYAxis {
                    AxisMarks(values: [0, 10, 20, 30]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes) min")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Draws a chart into a picture the size a photo would have.
    private static func render(@ViewBuilder _ content: () -> some View) -> PlatformImage {
        let renderer = ImageRenderer(
            content: content()
                .padding(28)
                .frame(width: 1024, height: 640)
                .background(Color(uiColor: .systemBackground))
        )
        renderer.scale = 2
        return renderer.uiImage ?? PlatformImage()
    }
}
