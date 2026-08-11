//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreLocation
import SpeziLocation
import SwiftUI


struct LocationView: View {
    @Environment(SpeziLocation.self) private var speziLocation
    @State private var location: CLLocation?
    @State private var authorizationStatus = "Not Authorized"
    
    
    var body: some View {
        VStack {
            Spacer()
            
            Text("Authorization Status: \(authorizationStatus)")
            
            if let location {
                Text("Latitude: \(location.coordinate.latitude)")
                Text("Longitude: \(location.coordinate.longitude)")
            } else {
                Text("Location not available")
            }
            
            Spacer()

            Button("Request When In Use Permission") {
                Task {
                    do {
                        let authorizationResult = try await speziLocation.requestWhenInUseAuthorization()
                        
                        if authorizationResult == .authorizedWhenInUse {
                            authorizationStatus = "Authorized when in use"
                        }
                    } catch {
                        print("An error occurred.")
                    }
                }
            }
            
            Button("Current Location") {
                Task {
                    do {
                        self.location = try await speziLocation.getLatestLocation()
                    } catch {
                        print("An error occurred.")
                    }
                }
            }
            
            Spacer()
        }
        .buttonStyle(.borderedProminent)
    }
}


#Preview {
    LocationView()
}
