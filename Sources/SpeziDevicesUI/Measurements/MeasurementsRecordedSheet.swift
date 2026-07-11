//
// This source file is part of the Stanford SpeziDevices open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import OSLog
@_spi(TestingSupport)
import SpeziDevices
import SpeziViews
import SwiftUI


struct TimeSubheadline: View {
    private let measurement: HealthKitMeasurement

    var body: some View {
        Group {
            if Calendar.current.isDateInToday(measurement.startDate) {
                Text("Today, \(Text(measurement.startDate, style: .time))", bundle: .module)
            } else {
                Text(.now, style: .date) + Text(verbatim: ", ") + Text(.now, style: .time)
            }
        }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    init(measurement: HealthKitMeasurement) {
        self.measurement = measurement
    }
}


/// A sheet view displaying one or many newly recorded measurements.
///
/// This view retrieves the pending measurements from the [`HealthMeasurements`](../../SpeziDevices/SpeziDevices.docc/SpeziDevices.md)
/// Module that is present in the SwiftUI environment.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct MeasurementsRecordedSheet: View {
    private let logger = Logger(subsystem: "edu.stanford.spezi.SpeziDevices", category: "MeasurementsRecordedSheet")
    private let saveSamples: @MainActor ([HKSample]) async throws -> Void

    @Environment(HealthMeasurements.self)
    private var measurements
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    @State private var selectedMeasurement: HealthKitMeasurement?

    @State private var viewState = ViewState.idle

    @MainActor private var forcedUnwrappedMeasurement: Binding<HealthKitMeasurement> {
        Binding {
            guard let selectedMeasurement = selectedMeasurement ?? measurements.pendingMeasurements.first else {
                preconditionFailure("Entered code path where selectedMeasurement was not set.")
            }
            return selectedMeasurement
        } set: { newValue in
            selectedMeasurement = newValue
        }
    }

    public var body: some View {
        NavigationStack { // swiftlint:disable:this closure_body_length
            Group {
                if measurements.pendingMeasurements.isEmpty && selectedMeasurement == nil {
                    ContentUnavailableView {
                        Label {
                            Text("No Pending Measurements", bundle: .module)
                        } icon: {
                            Image(systemName: "heart.text.square")
                                .accessibilityHidden(true)
                        }
                    } description: {
                        Text("There are currently no pending measurements. Conduct a measurement with a paired device while nearby.", bundle: .module)
                    }
                } else {
                    PaneContent {
                        Text("Measurement Recorded", bundle: .module)
                            .font(.title)
                            .fixedSize(horizontal: false, vertical: true)
                        if let selectedMeasurement {
                            TimeSubheadline(measurement: selectedMeasurement)
                        }
                    } subtitle: {
                        EmptyView()
                    } content: {
                        content
                    } action: {
                        action
                    }
                        .viewStateAlert(state: $viewState)
                        .interactiveDismissDisabled(viewState != .idle)
                        .dynamicTypeSize(.xSmall...DynamicTypeSize.accessibility3)
                        .onChange(of: selectedMeasurement, initial: true) {
                            if selectedMeasurement == nil {
                                selectedMeasurement = measurements.pendingMeasurements.first
                            }
                        }
                }
            }
                .toolbar {
                    DismissButton()
                }
        }
            .presentationDetents([.fraction(0.5), .large])
            .presentationCornerRadius(25)
    }


    @ViewBuilder @MainActor private var content: some View {
        if measurements.pendingMeasurements.count > 1 {
            TabView(selection: forcedUnwrappedMeasurement) {
                ForEach(measurements.pendingMeasurements) { measurement in
                    VStack {
                        MeasurementLayer(measurement: measurement)
                        Spacer()
                            .frame(minHeight: 30, idealHeight: 45, maxHeight: 60)
                            .fixedSize()
                    }
                        .tag(measurement)
                }
            }
#if !os(macOS)
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
#endif
        } else if let measurement = selectedMeasurement {
            MeasurementLayer(measurement: measurement)
        }
    }

    @ViewBuilder @MainActor private var action: some View {
        ConfirmMeasurementButton(viewState: $viewState) {
            guard let selectedMeasurement else {
                return
            }

            do {
                try await saveSamples(selectedMeasurement.samples)
            } catch {
                logger.error("Failed to save measurement samples: \(error)")
                throw error
            }


            logger.info("Saved measurement: \(String(describing: selectedMeasurement))")

            discardSelectedMeasurement(selectedMeasurement)
        } discard: {
            guard let selectedMeasurement else {
                return
            }

            discardSelectedMeasurement(selectedMeasurement)
        }
    }


    /// Create a new measurement sheet.
    public init(save saveSamples: @MainActor @escaping ([HKSample]) async throws -> Void) {
        self.saveSamples = saveSamples
    }


    @MainActor
    private func discardSelectedMeasurement(_ measurement: HealthKitMeasurement) {
        guard let index = measurements.pendingMeasurements.firstIndex(of: measurement) else {
            return
        }

        measurements.discardMeasurement(measurement)

        if index < measurements.pendingMeasurements.count {
            selectedMeasurement = measurements.pendingMeasurements[index]
        } else if let last = measurements.pendingMeasurements.last {
            // we do not set `selectedMeasurement` to nil if we are discarding the last measurement to have the
            // last measurement still display when the sheet is in its dismiss animation.
            selectedMeasurement = last
        }

        if measurements.pendingMeasurements.isEmpty {
            dismiss()
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @State @Previewable var isPresented = true
    return Text(verbatim: "")
        .sheet(isPresented: $isPresented) {
            MeasurementsRecordedSheet { samples in
                print("Saving samples \(samples)")
            }
        }
        .previewWith {
            HealthMeasurements(mock: [.weight(.mockWeighSample)])
        }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @State @Previewable var isPresented = true
    return Text(verbatim: "")
        .sheet(isPresented: $isPresented) {
            MeasurementsRecordedSheet { samples in
                print("Saving samples \(samples)")
            }
        }
        .previewWith {
            HealthMeasurements(mock: [.weight(.mockWeighSample, bmi: .mockBmiSample, height: .mockHeightSample)])
        }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @State @Previewable var isPresented = true
    return Text(verbatim: "")
        .sheet(isPresented: $isPresented) {
            MeasurementsRecordedSheet { samples in
                print("Saving samples \(samples)")
            }
        }
        .previewWith {
            HealthMeasurements(mock: [.bloodPressure(.mockBloodPressureSample, heartRate: .mockHeartRateSample)])
        }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @State @Previewable var isPresented = true
    return Text(verbatim: "")
        .sheet(isPresented: $isPresented) {
            MeasurementsRecordedSheet { samples in
                print("Saving samples \(samples)")
            }
        }
        .previewWith {
            HealthMeasurements(mock: [
                .weight(.mockWeighSample, bmi: .mockBmiSample, height: .mockHeightSample),
                .bloodPressure(.mockBloodPressureSample, heartRate: .mockHeartRateSample),
                .weight(.mockWeighSample)
            ])
        }
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @State @Previewable var isPresented = true
    return Text(verbatim: "")
        .sheet(isPresented: $isPresented) {
            MeasurementsRecordedSheet { samples in
                print("Saving samples \(samples)")
            }
        }
        .previewWith {
            HealthMeasurements()
        }
}
#endif
