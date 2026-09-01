//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import GroveViews
import PencilKit
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct AnnotateImageSheet: View {
    private static let editorCoordinateSpace = "AnnotationEditor"
    private static let imageMargin = CGFloat(12)
    private static let overlaySpacing = CGFloat(12)
    private static let overlayPadding = CGFloat(8)

    @Environment(\.dismiss) private var dismiss

    let task: Questionnaire.Task
    let config: AnnotateImageConfig
    let image: UIImage
    @Binding var response: QuestionnaireResponses.ImageAnnotation

    @State private var selectedRegion: AnnotateImageConfig.Region?
    @State private var history = AnnotationHistoryController()
    @State private var isShowingResetAlert = false
    @State private var editorHeight = CGFloat.zero
    @State private var promptBottom = CGFloat.zero
    @State private var regionPickerTop = CGFloat.zero

    var body: some View {
        NavigationStack {
            ZStack {
                AnnotationEditorCanvas(
                    image: image,
                    selectedRegion: selectedRegion,
                    drawing: $response.drawing,
                    contentInsets: contentInsets,
                    history: history
                )
                VStack(spacing: 0) {
                    AnnotationSheetHeader(title: task.title, subtitle: task.subtitle)
                        .padding(.horizontal, Self.imageMargin)
                        .onGeometryChange(
                            for: CGFloat.self,
                            of: { $0.frame(in: .named(Self.editorCoordinateSpace)).maxY }
                        ) { promptBottom = $0 }
                    Spacer(minLength: 0)
                    AnnotationRegionPicker(regions: config.regions, selectedRegion: $selectedRegion)
                        .onGeometryChange(
                            for: CGFloat.self,
                            of: { $0.frame(in: .named(Self.editorCoordinateSpace)).minY }
                        ) { regionPickerTop = $0 }
                }
                .padding(.vertical, Self.overlayPadding)
                .allowsHitTesting(true)
            }
            .coordinateSpace(name: Self.editorCoordinateSpace)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { editorHeight = $0 }
            .navigationTitle(Text("Annotate Image", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .makeBackgroundMatchFormBackground()
            .toolbar {
                toolbarContent
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: selectOnlyRegion)
    }

    private var contentInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: promptBottom + Self.overlaySpacing,
            left: Self.imageMargin,
            bottom: regionPickerTop > 0
                ? max(editorHeight - regionPickerTop, 0) + Self.overlaySpacing
                : 0,
            right: Self.imageMargin
        )
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if response.drawing.isEmpty {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: dismiss.callAsFunction) {
                    Label(LocalizedStringResource("Close", bundle: .module), systemImage: "xmark")
                }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .destructive, action: showResetConfirmation) {
                    Label(LocalizedStringResource("Remove", bundle: .module), systemImage: "trash")
                }
                .tint(.red)
                .confirmationDialog(
                    LocalizedStringResource("Remove Annotations", bundle: .module),
                    isPresented: $isShowingResetAlert
                ) {
                    Button(role: .destructive, action: resetAnnotations) {
                        Text("Remove", bundle: .module)
                    }
                } message: {
                    Text("Do you want to remove all annotations?", bundle: .module)
                }
            }
        }
        if history.canUndo || history.canRedo {
            if #available(iOS 26, macOS 26, *) {
                ToolbarSpacer(.fixed, placement: .cancellationAction)
            }
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(action: history.undo) {
                    Label(LocalizedStringResource("Undo", bundle: .module), systemImage: "arrow.uturn.backward")
                }
                .disabled(!history.canUndo)
                Button(action: history.redo) {
                    Label(LocalizedStringResource("Redo", bundle: .module), systemImage: "arrow.uturn.forward")
                }
                .disabled(!history.canRedo)
            }
        }
        if !response.drawing.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                if #available(iOS 26, macOS 26, *) {
                    Button(role: .confirm, action: dismiss.callAsFunction) {
                        Label(LocalizedStringResource("Done", bundle: .module), systemImage: "checkmark")
                    }
                } else {
                    Button(action: dismiss.callAsFunction) {
                        Label(LocalizedStringResource("Done", bundle: .module), systemImage: "checkmark")
                    }
                    .buttonStyleGlassProminent()
                }
            }
        }
    }

    private func selectOnlyRegion() {
        if selectedRegion == nil {
            selectedRegion = config.regions.first
        }
    }

    private func showResetConfirmation() {
        isShowingResetAlert = true
    }

    private func resetAnnotations() {
        response.drawing = .init()
        history.removeAllActions()
    }
}
#endif
