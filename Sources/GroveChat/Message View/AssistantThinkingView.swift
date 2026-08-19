//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


/// Surfaces a reasoning model's thinking phase: a live timer while it thinks, and the summary on tap once it's done.
@available(iOS 18, macOS 15, watchOS 11, *)
struct AssistantThinkingView: View {
    @Environment(\.locale) private var locale

    private let message: ChatEntity
    @State private var isShowingSheet = false

    private var thoughts: String {
        message.content.text ?? ""
    }

    private var sheetContent: some View {
        NavigationStack {
            ScrollView {
                if thoughts.isEmpty {
                    Text("Still Thinking…", bundle: .module)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 64)
                } else {
                    PlainMessageView.MarkdownView(text: thoughts)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
            .navigationTitle(Text("Model Thoughts", bundle: .module))
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    var body: some View {
        if case let .assistant(.thinking(startDate, endDate)) = message.role {
            Button {
                isShowingSheet = true
            } label: {
                label(startDate: startDate, endDate: endDate)
            }
            .buttonStyle(.plain)
            .disabled(message.complete && thoughts.isEmpty)
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .sheet(isPresented: $isShowingSheet) {
                sheetContent
            }
            .onChange(of: message.complete) { _, complete in
                // Nothing left to show once a thinking phase finishes without producing a summary.
                if complete && thoughts.isEmpty {
                    isShowingSheet = false
                }
            }
        }
    }

    init(_ message: ChatEntity) {
        self.message = message
    }

    @ViewBuilder
    private func label(startDate: Date?, endDate: Date?) -> some View {
        if message.complete {
            HStack(spacing: 4) {
                if let startDate, let endDate {
                    Text("Thought for \(format(endDate.timeIntervalSince(startDate), precise: false))", bundle: .module)
                } else if !thoughts.isEmpty {
                    Text("Model Thoughts", bundle: .module)
                }
                // Nothing to open without a summary, so the row shouldn't advertise that it can be tapped.
                if !thoughts.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
        } else {
            HStack(spacing: 6) {
                Text("Thinking…", bundle: .module)
                    .shimmering()
                if let startDate {
                    TimelineView(.periodic(from: startDate, by: 0.1)) { context in
                        Text(format(context.date.timeIntervalSince(startDate), precise: true))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// - Parameter precise: Whether to show fractional seconds, which the live counter does so it visibly ticks,
    ///     and the settled duration does not — a finished phase reads as a duration, not a stopwatch reading.
    private func format(_ totalSeconds: TimeInterval, precise: Bool) -> LocalizedStringResource {
        // Both parts have to come off the same value: rounding the seconds but truncating the minutes off the
        // raw one turns 65 s into "1:5 min", and 59.7 s into "60 sec".
        let total = max(0, precise ? totalSeconds : totalSeconds.rounded())
        let minutes = Int(total / 60)
        let seconds = total.truncatingRemainder(dividingBy: 60)
        let fractionLength = precise ? 1...2 : 0...0
        guard minutes > 0 else {
            let secondsStyle = FloatingPointFormatStyle<TimeInterval>.number
                .precision(.fractionLength(fractionLength))
                .locale(locale)
            return LocalizedStringResource("\(seconds, format: secondsStyle) sec", bundle: .module)
        }
        // Two integer digits, so "1:05 min" rather than "1:5 min".
        let secondsStyle = FloatingPointFormatStyle<TimeInterval>.number
            .precision(.integerAndFractionLength(integerLimits: 2...2, fractionLimits: fractionLength))
            .locale(locale)
        return LocalizedStringResource("\(String(minutes)):\(seconds, format: secondsStyle) min", bundle: .module)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// A slow highlight sweep, used to convey that the model is still working.
    @available(iOS 18, macOS 15, watchOS 11, *)
    fileprivate func shimmering() -> some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
            self.overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, phase - 0.2)),
                        .init(color: .primary.opacity(0.6), location: phase),
                        .init(color: .clear, location: min(1, phase + 0.2))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.plusLighter)
                .mask(self)
                .allowsHitTesting(false)
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    VStack(alignment: .leading, spacing: 20) {
        AssistantThinkingView(ChatEntity(
            role: .assistant(.thinking(startDate: .now.addingTimeInterval(-3), endDate: nil)),
            text: "",
            complete: false
        ))
        AssistantThinkingView(ChatEntity(
            role: .assistant(.thinking(startDate: .now.addingTimeInterval(-12), endDate: .now)),
            text: "First I considered the constraints, then I checked the edge cases."
        ))
    }
    .padding()
}
#endif
