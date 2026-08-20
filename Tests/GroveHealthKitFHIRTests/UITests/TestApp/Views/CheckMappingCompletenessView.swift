//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveHealthKitFHIR
import SwiftUI


struct CheckMappingCompletenessView: View {
    var body: some View {
        List {
            ForEach(HealthKitFHIRImplementationStatus.allCases, id: \.self) { status in
                let entries = HealthKitFHIRCatalog.entries.filter { $0.implementationStatus == status }
                if !entries.isEmpty {
                    Section(status.rawValue) {
                        ForEach(entries, id: \.sourceTypeIdentifier) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.title)
                                Text(entry.sourceTypeIdentifier)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if !entry.measurements.isEmpty {
                                    Text(entry.measurements.map(\.id).joined(separator: ", "))
                                        .font(.caption)
                                }
                                if let requirement = entry.requirement {
                                    Text(requirement)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("FHIR Coverage Matrix")
    }
}
