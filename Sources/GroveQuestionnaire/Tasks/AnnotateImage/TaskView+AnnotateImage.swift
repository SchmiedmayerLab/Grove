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


/// View that implements the UI for responding to "annotate image" tasks.
@available(iOS 18, macOS 15, watchOS 11, *)
struct AnnotateImageView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    private let image: UIImage?
    private let task: Questionnaire.Task
    private let config: AnnotateImageConfig
    @Binding private var response: QuestionnaireResponses.ImageAnnotation
    
    @State private var showSheet = false
    
    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(alignment: .top) {
                if let image {
                    AnnotationPreviewImage(image: image, drawing: $response.drawing)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel(Text("Image Missing", bundle: .module))
                        .frame(width: 50)
                }
                VStack(alignment: .leading) {
                    HStack {
                        let regions = config.regions.map(\.name).formatted()
                        Text("Mark \(regions)", bundle: .module)
                            .fontWeight(.medium)
                        Spacer()
                        let hasResponse = !response.isEmpty
                        Badge(hasResponse ? "Answered" : "Missing", bundle: .module)
                            .tint(hasResponse ? .green : .orange)
                    }
                    Text("Tap to annotate", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .tint(colorScheme.textLabelForegroundStyle)
            }
            .padding(.vertical, 8)
        }
        .disabled(image == nil)
        .accessibilityIdentifier("OpenImageAnnotationEditor")
        .accessibilityHint(Text("Opens an editor with drawing and zoom controls.", bundle: .module))
        .sheet(isPresented: $showSheet) {
            if let image {
                AnnotateImageSheet(task: task, config: config, image: image, response: $response)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    init(
        task: Questionnaire.Task,
        config: AnnotateImageConfig,
        response: Binding<QuestionnaireResponses.ImageAnnotation>
    ) {
        self.task = task
        self.config = config
        self._response = response
        self.image = config.inputImage.image()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnnotateImageView {
    static func ink(for region: AnnotateImageConfig.Region) -> PKInk {
        PKInk(.pen, color: UIColor(region.color))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnnotateImageView {
    private struct Badge<Label: View>: View {
        private let label: Label
        
        var body: some View {
            label
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }
        
        init(@ViewBuilder label: @MainActor () -> Label) {
            self.label = label()
        }
        
        init(_ title: LocalizedStringResource) where Label == Text {
            self.init {
                Text(title)
            }
        }
        
        init(_ title: LocalizedStringKey, bundle: Bundle) where Label == Text {
            self.init {
                Text(title, bundle: bundle)
            }
        }
    }
}


#endif
