//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import Foundation
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import PencilKit
import Testing
import UIKit


@Suite
@MainActor
struct ImageAnnotationExportTests {
    @Test
    func retinaDrawingIsFlattenedIntoFHIRAttachmentAtSourceResolution() throws {
        let baseImage = makeBaseImage()
        let annotation = QuestionnaireResponses.ImageAnnotation(drawing: makeDrawing())

        let flattened = try #require(annotation.draw(onto: baseImage))
        #expect(flattened.size == baseImage.size)
        #expect(flattened.scale == baseImage.scale)
        #expect(flattened.cgImage?.width == baseImage.cgImage?.width)
        #expect(flattened.cgImage?.height == baseImage.cgImage?.height)

        let task = GroveQuestionnaire.Questionnaire.Task(
            id: "annotation",
            title: "Annotate",
            kind: .annotateImage(.init(
                inputImage: .inlineData(try #require(baseImage.pngData())),
                regions: [.init(name: "Pain", color: .red)]
            ))
        )
        let answer = try #require(annotation.toFHIR(for: task).first)
        guard case .attachment(let attachment)? = answer.value,
              let encodedData = attachment.data?.value?.dataString,
              let data = Data(base64Encoded: encodedData),
              let exportedImage = UIImage(data: data) else {
            Issue.record("Expected the annotation to export as an inline PNG attachment")
            return
        }

        #expect(attachment.contentType?.value?.string == "image/png")
        #expect(exportedImage.cgImage?.width == baseImage.cgImage?.width)
        #expect(exportedImage.cgImage?.height == baseImage.cgImage?.height)
        #expect(data != baseImage.pngData())
    }

    private func makeBaseImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50), format: format).image { context in
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: 50, height: 50)))
        }
    }

    private func makeDrawing() -> PKDrawing {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 20, y: 50),
                timeOffset: 0,
                size: CGSize(width: 10, height: 10),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 80, y: 50),
                timeOffset: 1,
                size: CGSize(width: 10, height: 10),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        ]
        return PKDrawing(strokes: [
            PKStroke(
                ink: PKInk(.pen, color: .red),
                path: PKStrokePath(controlPoints: points, creationDate: .now)
            )
        ])
    }
}
#endif
