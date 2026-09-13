//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//
import GroveViews
import SwiftUI


/// The queue fanned out over the conversation: every waiting message on a card of its own, in the order they
/// will go, with a grip to move one and a pencil to take it back. A swipe to the left drops a card.
///
/// The cards sit on the same blur the composer floats on, reaching a little way above them and fading into the
/// conversation; with enough cards to scroll, it covers the whole of it. Anything outside the cards closes the
/// fan-out, and so does dropping the last one.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QueuedMessagesFanOut: View {
    private static let rowHeight: CGFloat = 64
    private static let removeThreshold: CGFloat = 96
    /// How far above the cards the blur reaches before it has faded into the conversation.
    private static let blurReach: CGFloat = 120

    let queue: ChatMessageQueue
    let cornerRadius: CGFloat

    /// The card being moved, with how far it has been dragged from where it sat.
    @State private var lift: (id: UUID, offset: CGFloat)?
    /// The card being pushed aside, with how far.
    @State private var swipe: (id: UUID, offset: CGFloat)?
    @State private var reorderCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {
                    queue.isExpanded = false
                }
                .accessibilityAction(named: Text("HIDE_QUEUED_MESSAGES", bundle: .module)) {
                    queue.isExpanded = false
                }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(queue.messages.enumerated()), id: \.element.id) { index, message in
                        card(message, at: index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .scrollTargetLayout()
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
            .scrollClipDisabled()
            .frame(maxHeight: Self.rowHeight * 6)
            .fixedSize(horizontal: false, vertical: true)
            .background(alignment: .bottom) {
                ProgressiveBlur(locations: [0, 0.6])
                    .padding(.top, -Self.blurReach)
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.selection, trigger: reorderCount)
        .accessibilityIdentifier("Queued Messages")
    }

    @ViewBuilder private var cardSurface: some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    private func card(_ message: QueuedMessage, at index: Int) -> some View {
        HStack(spacing: 12) {
            message.preview
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                queue.edit(message)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("EDIT_QUEUED_MESSAGE", bundle: .module))
            }
            .buttonStyle(.plain)
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text("REORDER_QUEUED_MESSAGE", bundle: .module))
                .gesture(reorderGesture(for: message, at: index))
        }
        .padding(.horizontal, 16)
        .frame(height: Self.rowHeight - 8)
        .background {
            cardSurface
        }
        .background(alignment: .trailing) {
            Image(systemName: "trash")
                .foregroundStyle(.white)
                .accessibilityHidden(true)
                .frame(width: Self.removeThreshold)
                .frame(maxHeight: .infinity)
                .background(.red, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .opacity(swipe?.id == message.id ? 1 : 0)
        }
        .offset(x: swipe?.id == message.id ? swipe?.offset ?? 0 : 0)
        .offset(y: lift?.id == message.id ? lift?.offset ?? 0 : 0)
        .zIndex(lift?.id == message.id ? 1 : 0)
        .simultaneousGesture(removeGesture(for: message))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Queued Message Card")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Lifts the card by its grip and moves it a row at a time as it crosses its neighbours.
    private func reorderGesture(for message: QueuedMessage, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let rows = Int((value.translation.height / Self.rowHeight).rounded())
                let target = min(max(index + rows, 0), queue.messages.count - 1)
                if target != index, let current = queue.messages.firstIndex(where: { $0.id == message.id }) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        queue.messages.move(fromOffsets: IndexSet(integer: current), toOffset: target > current ? target + 1 : target)
                    }
                    reorderCount += 1
                    lift = (message.id, value.translation.height - CGFloat(target - index) * Self.rowHeight)
                } else {
                    lift = (message.id, value.translation.height - CGFloat(target - index) * Self.rowHeight)
                }
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    lift = nil
                }
            }
    }

    /// Pushes the card aside to the left; far enough, and it is dropped.
    private func removeGesture(for message: QueuedMessage) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height), value.translation.width < 0 else {
                    return
                }
                swipe = (message.id, max(value.translation.width, -Self.removeThreshold * 1.5))
            }
            .onEnded { value in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    if value.translation.width < -Self.removeThreshold {
                        queue.remove(message)
                    }
                    swipe = nil
                }
            }
    }
}
