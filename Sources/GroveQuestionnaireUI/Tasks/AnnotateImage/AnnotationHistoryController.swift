//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import Foundation
import Observation
import PencilKit


@MainActor
protocol AnnotationHistoryControllerDelegate: AnyObject {
    func annotationHistoryDidRestore(_ drawing: PKDrawing)
}


/// Bridges PencilKit drawing changes into an undo manager that can drive SwiftUI controls.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
@Observable
final class AnnotationHistoryController {
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private let undoManager = UndoManager()
    @ObservationIgnored private weak var canvasView: PKCanvasView?
    @ObservationIgnored private weak var delegate: (any AnnotationHistoryControllerDelegate)?
    @ObservationIgnored private(set) var isPerformingHistoryAction = false
    @ObservationIgnored private var pendingChangeTask: Task<Void, Never>?
    @ObservationIgnored private var drawingBeforePendingChange: PKDrawing?

    func attach(to canvasView: PKCanvasView, delegate: any AnnotationHistoryControllerDelegate) {
        self.canvasView = canvasView
        self.delegate = delegate
        refreshAvailability()
    }

    func undo() {
        guard undoManager.canUndo else {
            return
        }
        isPerformingHistoryAction = true
        undoManager.undo()
        finishHistoryAction()
    }

    func redo() {
        guard undoManager.canRedo else {
            return
        }
        isPerformingHistoryAction = true
        undoManager.redo()
        finishHistoryAction()
    }

    func removeAllActions() {
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        drawingBeforePendingChange = nil
        undoManager.removeAllActions()
        refreshAvailability()
    }

    func drawingDidChange(from previousDrawing: PKDrawing) {
        guard !isPerformingHistoryAction else {
            return
        }
        drawingBeforePendingChange = drawingBeforePendingChange ?? previousDrawing
        pendingChangeTask?.cancel()
        pendingChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            self?.finishPendingChange()
        }
    }

    private func finishHistoryAction() {
        isPerformingHistoryAction = false
        refreshAvailability()
    }

    private func finishPendingChange() {
        guard let drawingBeforePendingChange,
              let drawing = canvasView?.drawing else {
            return
        }
        pendingChangeTask = nil
        self.drawingBeforePendingChange = nil
        guard drawingBeforePendingChange != drawing else {
            return
        }
        registerUndo(restoring: drawingBeforePendingChange)
        refreshAvailability()
    }

    private func registerUndo(restoring drawing: PKDrawing) {
        undoManager.registerUndo(withTarget: self) { controller in
            controller.restore(drawing)
        }
        undoManager.setActionName(String(localized: "Drawing", bundle: .module))
    }

    private func restore(_ drawing: PKDrawing) {
        guard let canvasView else {
            return
        }
        let replacedDrawing = canvasView.drawing
        registerUndo(restoring: replacedDrawing)
        isPerformingHistoryAction = true
        canvasView.drawing = drawing
        delegate?.annotationHistoryDidRestore(drawing)
    }

    private func refreshAvailability() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}
#endif
