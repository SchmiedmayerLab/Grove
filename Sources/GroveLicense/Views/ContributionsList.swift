//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftPackageList
public import SwiftUI


/// Present a `ContributionsList` including all used Swift Packages to the user.
///
/// The following example shows how to use the ContributionsList:
/// ```swift
/// import GroveLicense
/// import SwiftUI
///
/// struct ExamplePackageDependenciesView: View {
///
///     var body: some View {
///         ContributionsList(appName: "ExamplePackageDependenciesApp", projectLicense: "MIT")
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ContributionsList: View {
    struct ProjectInfo {
        let name: AppName
        let url: URL?
        let license: License?
    }
    
    private let packages: [Package]
    private let projectInfo: ProjectInfo
    
    public var body: some View {
        Form {
            Section {
                PackageCell(config: appSectionRowConfig)
            }
            Section {
                ForEach(packages, id: \.identity) { package in
                    PackageCell(package: package)
                }
            } header: {
                let appName = projectInfo.name.value
                if !appName.isEmpty {
                    Text("Dependencies used by \(projectInfo.name.value)", bundle: .module)
                } else {
                    Text("Dependencies", bundle: .module)
                }
            } footer: {
                Text("Please refer to the individual repository links for packages without license labels.", bundle: .module)
            }
        }
        .navigationTitle(LocalizedStringResource("License Information", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var appSectionRowConfig: PackageCell.Config {
        PackageCell.Config(
            name: projectInfo.name.value,
            versionString: { () -> String? in
                if projectInfo.name == .automatic, let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    "Version: \(string)"
                } else {
                    nil
                }
            }(),
            url: projectInfo.url,
            license: projectInfo.license,
            licenseText: nil
        )
    }
    
    private init(packages: [Package], projectInfo: ProjectInfo) {
        self.packages = packages.sorted(using: KeyPathComparator(\.name, comparator: String.Comparator(options: .caseInsensitive)))
        self.projectInfo = projectInfo
    }
    
    /// Creates a `ContributionsList`.
    ///
    /// - parameter appName: The name of the app to be rendered in the information text at the top of the view.
    ///     Defaults to ``AppName/automatic``, which reads the name from the main Bundle.
    /// - parameter projectLicense: Optional SPDX-License-Identifier to inform user about the project's license.
    /// - parameter projectUrl: Optional URL to the project whose contributions are displayed.
    /// - parameter additionalPackages: Additional entries that should be displayed in the list but are not present in the app's SPM dependencies.
    ///     Intended for non-SPM dependencies.
    public init(
        appName: AppName = .automatic,
        projectLicense: License? = nil,
        projectUrl: URL? = nil,
        additionalPackages: [Package] = []
    ) {
        self.init(
            packages: PackageList.spmPackages + additionalPackages,
            projectInfo: .init(name: appName, url: projectUrl, license: projectLicense)
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ContributionsList {
    public struct AppName: Hashable, ExpressibleByStringLiteral, Sendable {
        /// The app name as present in the main bundle.
        public static let automatic = Self(value: Bundle.main.applicationName ?? "")
        
        let value: String
        
        private init(value: String) {
            self.value = value
        }
        
        /// Creates a new app name from a string literal.
        public init(stringLiteral value: String) {
            self.value = value
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    let mockPackages = [
        Package(
            kind: .remoteSourceControl,
            identity: "MockPackage",
            name: "MockPackage",
            version: "1.0",
            branch: nil,
            revision: "0",
            location: "https://github.com/SchmiedmayerLab/MockPackage.git",
            license: "MIT License"
        )
    ]
    return ContributionsList(appName: "TestApp", projectLicense: .mit, additionalPackages: mockPackages)
}
#endif
