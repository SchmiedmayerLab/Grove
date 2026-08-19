//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import XCTestApp


struct GroveViewsTargetsTests: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @State var enableFlippedLayoutDirection = false
    @State var presentingGroveViews = false
    @State var presentingGrovePersonalInfo = false
    @State var presentingGroveValidation = false
    @State var presentingManagedNavigationStack = false
    @State var presentingToolbarAsyncButtonSheet = false

#if os(macOS)
    @MainActor
    private var idealWidth: CGFloat {
        guard let width = NSApp.keyWindow?.contentView?.bounds.width else {
            return 500
        }
        return max(width - 100, 300)
    }

    @MainActor
    private var idealHeight: CGFloat {
        guard let height = NSApp.keyWindow?.contentView?.bounds.height else {
            return 400
        }
        return max(height - 50, 250)
    }
#endif

    
    private var effectiveLayoutDirection: LayoutDirection {
        guard enableFlippedLayoutDirection else {
            return layoutDirection
        }
        return switch layoutDirection {
        case .leftToRight: .rightToLeft
        case .rightToLeft: .leftToRight
        @unknown default: layoutDirection
        }
    }

    var body: some View {
        // swiftlint:disable:next closure_body_length
        NavigationStack {
            // swiftlint:disable:next closure_body_length
            List {
                Button("GroveViews") {
                    presentingGroveViews = true
                }
                Button("GrovePersonalInfo") {
                    presentingGrovePersonalInfo = true
                }
                Button("GroveValidation") {
                    presentingGroveValidation = true
                }
                Button("ManagedNavigationStack") {
                    presentingManagedNavigationStack = true
                }
                #if canImport(PencilKit) && !os(macOS)
                NavigationLink("CanvasTest") {
                    CanvasTestView()
                }
                #endif
                
                Section("Other") {
                    Button("AsyncButton Toolbar Behaviour") {
                        presentingToolbarAsyncButtonSheet = true
                    }
                }

                Section {
                    NavigationLink("ViewState") {
                        ViewStateExample()
                    }
                    NavigationLink("NameFields") {
                        NameFieldsExample()
                    }
                    NavigationLink("Validation TextField") {
                        ValidationExample()
                    }
                    NavigationLink("Tiles") {
                        TileExample()
                    }
                    NavigationLink("SkeletonLoading") {
                        SkeletonLoadingExample()
                    }
                } header: {
                    Text("Examples")
                } footer: {
                    Text("Example Views to take screenshots for GroveViews")
                }
            }
            .navigationTitle("Targets")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Toggle("Flip Layout Direction", isOn: $enableFlippedLayoutDirection)
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Flip Layout Direction", isOn: $enableFlippedLayoutDirection)
                }
                #endif
            }
        }
        .environment(\.layoutDirection, effectiveLayoutDirection)
        .sheet(isPresented: $presentingGroveViews) {
            TestAppTestsView<GroveViewsTests>(showCloseButton: true)
                .environment(\.layoutDirection, effectiveLayoutDirection)
#if os(macOS)
                .frame(minWidth: idealWidth, minHeight: idealHeight)
#endif
        }
        .sheet(isPresented: $presentingGrovePersonalInfo) {
            TestAppTestsView<GrovePersonalInfoTests>(showCloseButton: true)
#if os(macOS)
                .frame(minWidth: idealWidth, minHeight: idealHeight)
#endif
        }
        .sheet(isPresented: $presentingGroveValidation) {
            TestAppTestsView<GroveValidationTests>(showCloseButton: true)
#if os(macOS)
                .frame(minWidth: idealWidth, minHeight: idealHeight)
#endif
        }
        .sheet(isPresented: $presentingManagedNavigationStack) {
            ManagedNavigationStackTestView()
#if os(macOS)
                .frame(minWidth: idealWidth, minHeight: idealHeight)
#endif
        }
        .sheet(isPresented: $presentingToolbarAsyncButtonSheet) {
            AsyncButtonToolbarTestSheet()
        }
    }
}


#if DEBUG
#Preview {
    GroveViewsTargetsTests()
}
#endif
