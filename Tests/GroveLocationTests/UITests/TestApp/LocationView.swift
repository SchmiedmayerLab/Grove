//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreLocation
import GroveLocation
import SwiftUI


struct LocationView: View {
    @Environment(GroveLocation.self) private var groveLocation
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
                        let authorizationResult = try await groveLocation.requestWhenInUseAuthorization()
                        
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
                        self.location = try await groveLocation.getLatestLocation()
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
