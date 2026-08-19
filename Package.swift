// swift-tools-version:6.3
//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CompilerPluginSupport
import class Foundation.FileManager
import class Foundation.ProcessInfo
import struct Foundation.URL
import PackageDescription


/// Toggle SwiftLint by setting this to `true`.
let enableSwiftLint = false

// Lowered (iOS 15 / macOS 12 / watchOS 8) deployment targets are OFF by default, so the default
// package graph may depend on iOS-18+-only dependencies. The deployment-floor CI legs
// (Scripts/build-floor.sh) opt in via this environment variable; the planned iOS-15 mirror repo
// instead flips the default (and disables all traits).
let isLoweredDeploymentTargetEnabled = Context.environment["GROVE_LOWERED_DEPLOYMENT_TARGETS"] == "1"

// FHIRModels >= 0.9 cannot link for armv7k: its struct-based models exceed the 32-bit Mach-O
// scattered-relocation limit, and the App Store rejects watchOS-8-target binaries that lack the
// armv7k slice (ITMS-90733) — so no watchOS-8 consumer could ever ship the FHIR stack anyway.
// In the lowered configuration the FHIRModels dependency (and, transitively, every target whose
// closure embeds it) is therefore unavailable on watchOS; everything else keeps the watchOS 8 floor.
// The floor-build analyzer (Scripts/build-floor.sh) understands this convention: an *external*
// product dependency carrying a platform-only condition marks its target as unsupported on the
// excluded platforms.
let fhirModelsCondition: TargetDependencyCondition? = isLoweredDeploymentTargetEnabled
    ? .when(platforms: [.iOS, .macOS, .macCatalyst, .visionOS, .tvOS, .linux])
    : nil

/// The platforms that ship the SwiftUI-based layers. Linux gets the LLM core without them.
let applePlatformsOnly: TargetDependencyCondition? = .when(
    platforms: [.iOS, .macOS, .macCatalyst, .visionOS, .tvOS, .watchOS]
)

var defaultPlugins: [Target.PluginUsage] {
    enableSwiftLint ? [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")] : []
}

let defaultSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault")
]

let textualTrait = "Textual"
let mlxTrait = "MLX"
let researchKitTrait = "ResearchKit"
// MLX and ResearchKit stay opt-in: they pull in large dependencies a consumer may not want in its graph.
let optionalPackageTraits = [mlxTrait, researchKitTrait]

// Rich Markdown rendering is what the chat is expected to look like — tables, code blocks and all — so Textual is
// on unless a consumer deliberately turns it off, rather than something every app has to remember to ask for.
let defaultEnabledTraits: Set<String> = if isLoweredDeploymentTargetEnabled {
    []
} else if Context.environment["GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS"] == "1" {
    Set(optionalPackageTraits + [textualTrait])
} else {
    [textualTrait]
}
// Compile/test builds can exclude DocC catalogs to avoid SwiftPM unhandled-file warnings.
// Documentation builds keep them included so DocC can resolve articles and assets.
let excludeDocCCatalogs = Context.environment["GROVE_EXCLUDE_DOCC_CATALOGS"] == "1"

let packagePlatforms: [SupportedPlatform] = if isLoweredDeploymentTargetEnabled {
    [.iOS(.v15), .macOS(.v12), .watchOS(.v9)]
} else {
    [.iOS(.v18), .macOS(.v15), .watchOS(.v11)]
}

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

let reusableTargetExcludes = [
    "CITATION.cff",
    "CONTRIBUTORS.md",
    "LICENSE",
    "LICENSE.md",
    "LICENSES",
    "README.md",
    "REUSE.toml"
]

func targetExcludes(_ targetName: String, additional: [String] = []) -> [String] {
    reusableExcludes(in: "Sources/\(targetName)", additional: additional)
}

func testTargetExcludes(_ targetName: String, additional: [String] = []) -> [String] {
    reusableExcludes(in: "Tests/\(targetName)", additional: additional)
}

func reusableExcludes(in targetPath: String, additional: [String] = []) -> [String] {
    let existingAdditionalExcludes = existingExcludes(in: targetPath, matching: additional)
    let excludes = existingExcludes(in: targetPath, matching: reusableTargetExcludes)
        + doccCatalogExcludes(in: targetPath, skipping: existingAdditionalExcludes)
        + licenseExcludes(in: targetPath, skipping: existingAdditionalExcludes)
        + existingAdditionalExcludes
    var seenExcludes: Set<String> = []
    return excludes.filter { seenExcludes.insert($0).inserted }
}

func existingExcludes(in targetPath: String, matching candidates: [String]) -> [String] {
    let targetDirectory = packageDirectory.appendingPathComponent(targetPath, isDirectory: true)
    return candidates.filter { FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent($0).path) }
}

func licenseExcludes(in targetPath: String, skipping skippedExcludes: [String]) -> [String] {
    matchingFiles(in: targetPath, skipping: skippedExcludes) { relativePath in
        relativePath.hasSuffix(".license")
    }
}

func doccCatalogExcludes(in targetPath: String, skipping skippedExcludes: [String]) -> [String] {
    guard excludeDocCCatalogs else {
        return []
    }
    return matchingFiles(in: targetPath, skipping: skippedExcludes) { relativePath in
        relativePath.hasSuffix(".docc")
    }
}

func matchingFiles(in targetPath: String, skipping skippedExcludes: [String], where matches: (String) -> Bool) -> [String] {
    let targetDirectory = packageDirectory.appendingPathComponent(targetPath, isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(atPath: targetDirectory.path) else {
        return []
    }
    var excludes: [String] = []
    while let relativePath = enumerator.nextObject() as? String {
        guard !skippedExcludes.contains(where: { relativePath == $0 || relativePath.hasPrefix("\($0)/") }) else {
            enumerator.skipDescendants()
            continue
        }
        if matches(relativePath) {
            excludes.append(relativePath)
            enumerator.skipDescendants()
        }
    }
    return excludes.sorted()
}

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/antlr/antlr4.git", from: "4.13.1"),
    // 0.9.1 lower bound: 0.9.0 breaks the DSTU2 models (BackboneElement typealias collapse).
    // <0.9.2 upper bound: 0.9.2 raises FHIRModels' deployment targets to iOS 16/macOS 13 (OSAllocatedUnfairLock),
    // which conflicts with the lowered-deployment-target builds (`isLoweredDeploymentTargetEnabled`).
    .package(url: "https://github.com/SchmiedmayerLab/FHIRModels.git", .upToNextMinor(from: "0.9.3")),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.1.0"),
    .package(url: "https://github.com/PhoneNumberKit/PhoneNumberKit.git", from: "5.0.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.16.0")),
    .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.3"),
    .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.4"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.2"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.59.0"),
    .package(url: "https://github.com/apple/swift-numerics.git", from: "1.1.1"),
    .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.13.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.8.0"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.1.0"),
    .package(url: "https://github.com/FelixHerrmann/swift-package-list.git", from: "4.8.0"),
    .package(url: "https://github.com/gonzalezreal/textual.git", .upToNextMinor(from: "0.3.1")),
    .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMinor(from: "0.29.1")),
    .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "2.29.1"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.19.2"),
    .package(url: "https://github.com/SchmiedmayerLab/ResearchKit.git", "3.1.4"..<"3.2.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
    .package(url: "https://github.com/dfed/swift-testing-expectation.git", .upToNextMinor(from: "0.1.4")),
    .package(url: "https://github.com/techprimate/TPPDF.git", from: "2.6.1"),
    .package(url: "https://github.com/SchmiedmayerLab/zstd.git", exact: "1.5.8-beta.1")
]

if enableSwiftLint {
    dependencies.append(
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", from: "0.63.2")
    )
}


var products: [Product] = [
    // MARK: FHIRModelsExtensions
    .library(name: "FHIRModelsExtensions", targets: ["FHIRModelsExtensions"]),
    .library(name: "FHIRPathParser", targets: ["FHIRPathParser"]),
    .library(name: "FHIRQuestionnaires", targets: ["FHIRQuestionnaires"]),
    // MARK: ResearchKitOnFHIR
    .library(name: "ResearchKitOnFHIR", targets: ["ResearchKitOnFHIR"]),
    // MARK: Grove
    .library(name: "Grove", targets: ["Grove"]),
    .library(name: "GroveTesting", targets: ["GroveTesting"]),
    .library(name: "XCTGrove", targets: ["XCTGrove"]),
    // MARK: GroveAccessGuard
    .library(name: "GroveAccessGuard", targets: ["GroveAccessGuard"]),
    // MARK: GroveAccount
    .library(name: "GroveAccount", targets: ["GroveAccount"]),
    .library(name: "XCTGroveAccount", targets: ["XCTGroveAccount"]),
    .library(name: "GroveAccountPhoneNumbers", targets: ["GroveAccountPhoneNumbers"]),
    // MARK: GroveBluetooth
    .library(name: "GroveBluetoothServices", targets: ["GroveBluetoothServices"]),
    .library(name: "GroveBluetooth", targets: ["GroveBluetooth"]),
    // MARK: GroveChat
    .library(name: "GroveChat", targets: ["GroveChat"]),
    // MARK: GroveConsent
    .library(name: "GroveConsent", targets: ["GroveConsent"]),
    // MARK: GroveContact
    .library(name: "GroveContact", targets: ["GroveContact"]),
    // MARK: GroveDevices
    .library(name: "GroveDevices", targets: ["GroveDevices"]),
    .library(name: "GroveDevicesUI", targets: ["GroveDevicesUI"]),
    .library(name: "GroveOmron", targets: ["GroveOmron"]),
    // MARK: GroveFHIR
    .library(name: "GroveFHIR", targets: ["GroveFHIR"]),
    .library(name: "GroveFHIRMockPatients", targets: ["GroveFHIRMockPatients"]),
    // MARK: GroveFileFormats
    .library(name: "EDFFormat", targets: ["EDFFormat"]),
    // MARK: GroveFirebase
    .library(name: "GroveFirebaseAccount", targets: ["GroveFirebaseAccount"]),
    .library(name: "GroveFirebaseConfiguration", targets: ["GroveFirebaseConfiguration"]),
    .library(name: "GroveFirestore", targets: ["GroveFirestore"]),
    .library(name: "GroveFirebaseStorage", targets: ["GroveFirebaseStorage"]),
    .library(name: "GroveFirebaseAccountStorage", targets: ["GroveFirebaseAccountStorage"]),
    // MARK: GroveFoundation
    .library(name: "GroveFoundation", targets: ["GroveFoundation"]),
    .library(name: "GroveLocalization", targets: ["GroveLocalization"]),
    .library(name: "ThreadLocal", targets: ["ThreadLocal"]),
    // MARK: GroveHealthKit
    .library(name: "GroveHealthKit", targets: ["GroveHealthKit"]),
    .library(name: "GroveHealthKitBulkExport", targets: ["GroveHealthKitBulkExport"]),
    .library(name: "GroveHealthKitUI", targets: ["GroveHealthKitUI"]),
    .library(name: "GroveHealthKitFHIR", targets: ["GroveHealthKitFHIR"]),
    // MARK: GroveLLM
    .library(name: "GroveLLM", targets: ["GroveLLM"]),
    .library(name: "GroveLLMLocal", targets: ["GroveLLMLocal"]),
    .library(name: "GroveLLMLocalDownload", targets: ["GroveLLMLocalDownload"]),
    .library(name: "GroveLLMOpenAI", targets: ["GroveLLMOpenAI"]),
    .library(name: "GroveLLMOpenAIRealtime", targets: ["GroveLLMOpenAIRealtime"]),
    .library(name: "GroveLLMAnthropic", targets: ["GroveLLMAnthropic"]),
    .library(name: "GroveLLMGemini", targets: ["GroveLLMGemini"]),
    .library(name: "GroveLLMFoundationModels", targets: ["GroveLLMFoundationModels"]),
    // MARK: GroveLicense
    .library(name: "GroveLicense", targets: ["GroveLicense"]),
    // MARK: GroveLocation
    .library(name: "GroveLocation", targets: ["GroveLocation"]),
    // MARK: GroveNetworking
    .library(name: "ByteCoding", targets: ["ByteCoding"]),
    .library(name: "GroveNumerics", targets: ["GroveNumerics"]),
    .library(name: "XCTByteCoding", targets: ["XCTByteCoding"]),
    .library(name: "ByteCodingTesting", targets: ["ByteCodingTesting"]),
    // MARK: GroveNotifications
    .library(name: "GroveNotifications", targets: ["GroveNotifications"]),
    .library(name: "XCTGroveNotifications", targets: ["XCTGroveNotifications"]),
    .library(name: "XCTGroveNotificationsUI", targets: ["XCTGroveNotificationsUI"]),
    // MARK: GroveOnboarding
    .library(name: "GroveOnboarding", targets: ["GroveOnboarding"]),
    // MARK: GroveQuestionnaire
    .library(name: "GroveQuestionnaire", targets: ["GroveQuestionnaire"]),
    .library(name: "GroveQuestionnaireCatalog", targets: ["GroveQuestionnaireCatalog"]),
    .library(name: "GroveQuestionnaireFHIR", targets: ["GroveQuestionnaireFHIR"]),
    .library(name: "GroveQuestionnaireLegacy", targets: ["GroveQuestionnaireLegacy"]),
    .library(name: "XCTGroveQuestionnaire", targets: ["XCTGroveQuestionnaire"]),
    // MARK: GroveScheduler
    .library(name: "GroveScheduler", targets: ["GroveScheduler"]),
    // MARK: GroveSensorKit
    .library(name: "GroveSensorKit", targets: ["GroveSensorKit"]),
    // MARK: GroveSpeech
    .library(name: "GroveSpeechRecognizer", targets: ["GroveSpeechRecognizer"]),
    .library(name: "GroveSpeechSynthesizer", targets: ["GroveSpeechSynthesizer"]),
    // MARK: GroveStorage
    .library(name: "GroveLocalStorage", targets: ["GroveLocalStorage"]),
    .library(name: "GroveKeychainStorage", targets: ["GroveKeychainStorage"]),
    // MARK: GroveStudy
    .library(name: "GroveStudyDefinition", targets: ["GroveStudyDefinition"]),
    // MARK: GroveViews
    .library(name: "GroveViews", targets: ["GroveViews"]),
    .library(name: "GrovePersonalInfo", targets: ["GrovePersonalInfo"]),
    .library(name: "GroveValidation", targets: ["GroveValidation"]),
    // MARK: XCTHealthKit
    .library(name: "XCTHealthKit", targets: ["XCTHealthKit"]),
    // MARK: RuntimeAssertions
    .library(name: "RuntimeAssertions", targets: ["RuntimeAssertions"]),
    .library(name: "RuntimeAssertionsTesting", targets: ["RuntimeAssertionsTesting"]),
    // MARK: XCTestExtensions
    .library(name: "XCTestApp", targets: ["XCTestApp"]),
    .library(name: "XCTestExtensions", targets: ["XCTestExtensions"])
]

#if canImport(Darwin)
products += [
    // MARK: GroveScheduler
    .library(name: "GroveSchedulerUI", targets: ["GroveSchedulerUI"]),
    // MARK: GroveStudy
    .library(name: "GroveStudy", targets: ["GroveStudy"])
]
#endif


var targets: [Target] = [
    // MARK: FHIRModelsExtensions
    .target(
        name: "FHIRModelsExtensions",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "FHIRPathParser"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .product(name: "ModelsDSTU2", package: "FHIRModels", condition: fhirModelsCondition)
        ],
        exclude: targetExcludes("FHIRModelsExtensions", additional: ["FHIR+ExtensionUtils.swift.gyb"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "FHIRPathParser",
        dependencies: [
            .product(name: "Antlr4", package: "antlr4")
        ],
        exclude: targetExcludes("FHIRPathParser", additional: ["ANTLUtils"]),
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "FHIRQuestionnaires",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition)
        ],
        exclude: targetExcludes("FHIRQuestionnaires"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "FHIRModelsExtensionsTests",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRQuestionnaires")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "FHIRPathParserTests",
        dependencies: [
            .target(name: "FHIRPathParser")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveHealthKitFHIR
    .macro(
        name: "GroveHealthKitFHIRMacrosImpl",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveHealthKitFHIRMacros",
        dependencies: [
            .target(name: "GroveHealthKitFHIRMacrosImpl")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveHealthKitFHIR",
        dependencies: [
            .target(name: "GroveHealthKitFHIRMacros"),
            .target(name: "GroveHealthKit"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .product(name: "ModelsDSTU2", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions")
        ],
        exclude: targetExcludes("GroveHealthKitFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveHealthKitFHIRTests",
        dependencies: [
            .target(name: "GroveHealthKitFHIR"),
            .target(name: "GroveFoundation")
        ],
        exclude: testTargetExcludes("GroveHealthKitFHIRTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveHealthKitFHIRMacrosTests",
        dependencies: [
            .target(name: "GroveHealthKitFHIRMacros"),
            .target(name: "GroveHealthKitFHIRMacrosImpl"),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: ResearchKitOnFHIR
    .target(
        name: "ResearchKitOnFHIR",
        dependencies: [
            .product(name: "ResearchKit", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .product(name: "ResearchKitSwiftUI", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRPathParser")
        ],
        exclude: targetExcludes("ResearchKitOnFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "ResearchKitOnFHIRTests",
        dependencies: [
            .target(name: "ResearchKitOnFHIR", condition: .when(traits: [researchKitTrait])),
            .target(name: "FHIRQuestionnaires")
        ],
        exclude: testTargetExcludes("ResearchKitOnFHIRTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: Grove
    .target(
        name: "Grove",
        dependencies: [
            .target(name: "GroveFoundation"),
            .target(name: "RuntimeAssertions"),
            .product(name: "OrderedCollections", package: "swift-collections")
        ],
        exclude: targetExcludes("Grove"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveTesting",
        dependencies: [
            .target(name: "Grove")
        ],
        exclude: targetExcludes("GroveTesting"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTGrove",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveTests",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveTesting"),
            .product(name: "TestingExpectation", package: "swift-testing-expectation")
        ],
        exclude: testTargetExcludes("GroveTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings + [
            .define("DEBUG", .when(configuration: .debug))
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveAccessGuard
    .target(
        name: "GroveAccessGuard",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "Grove"),
            .target(name: "GroveKeychainStorage"),
            .target(name: "GroveViews"),
            .target(name: "GroveFoundation")
        ],
        exclude: targetExcludes("GroveAccessGuard"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveAccessGuardTests",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveAccessGuard"),
            .target(name: "GroveTesting"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("GroveAccessGuardTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveAccount
    .macro(
        name: "GroveAccountMacros",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveAccount",
        dependencies: [
            .target(name: "GroveFoundation"),
            .target(name: "Grove"),
            .target(name: "GroveViews"),
            .target(name: "GrovePersonalInfo"),
            .target(name: "GroveValidation"),
            .target(name: "GroveLocalStorage"),
            .target(name: "RuntimeAssertions"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "Atomics", package: "swift-atomics"),
            .target(name: "GroveAccountMacros")
        ],
        exclude: targetExcludes("GroveAccount"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTGroveAccount",
        dependencies: [
            .target(name: "GroveAccount"),
            .target(name: "XCTestExtensions")
        ],
        exclude: targetExcludes("XCTGroveAccount"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveAccountPhoneNumbers",
        dependencies: [
            .target(name: "GroveAccount"),
            .product(name: "PhoneNumberKit", package: "PhoneNumberKit")
        ],
        exclude: targetExcludes("GroveAccountPhoneNumbers"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveAccountTests",
        dependencies: [
            .target(name: "GroveAccount"),
            .target(name: "GroveAccountPhoneNumbers"),
            .target(name: "Grove"),
            .target(name: "GroveTesting"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("GroveAccountTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveAccountMacrosTests",
        dependencies: [
            .target(name: "GroveAccountMacros"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveBluetooth
    .target(
        name: "GroveBluetooth",
        dependencies: [
            .target(name: "Grove"),
            .product(name: "NIOCore", package: "swift-nio"),
            .target(name: "GroveViews"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .target(name: "GroveFoundation"),
            .target(name: "ByteCoding"),
            .product(name: "Atomics", package: "swift-atomics")
        ],
        exclude: targetExcludes("GroveBluetooth", additional: ["bin"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveBluetoothServices",
        dependencies: [
            .target(name: "GroveBluetooth"),
            .target(name: "ByteCoding"),
            .target(name: "GroveNumerics")
        ],
        exclude: targetExcludes("GroveBluetoothServices"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .executableTarget(
        name: "TestPeripheral",
        dependencies: [
            .target(name: "GroveBluetooth"),
            .target(name: "GroveBluetoothServices"),
            .target(name: "ByteCoding")
        ],
        exclude: targetExcludes("TestPeripheral"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveBluetoothTests",
        dependencies: [
            .target(name: "GroveBluetooth"),
            .target(name: "GroveBluetoothServices")
        ],
        exclude: testTargetExcludes("GroveBluetoothTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveBluetoothServicesTests",
        dependencies: [
            .target(name: "GroveBluetooth"),
            .target(name: "GroveBluetoothServices"),
            .product(name: "NIOCore", package: "swift-nio"),
            .target(name: "ByteCodingTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveChat
    .target(
        name: "GroveChat",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveSpeechRecognizer"),
            .target(name: "GroveSpeechSynthesizer"),
            .target(name: "GroveViews"),
            .product(name: "Textual", package: "textual", condition: .when(traits: [textualTrait]))
        ],
        exclude: targetExcludes("GroveChat"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveChatTests",
        dependencies: [
            .target(name: "GroveChat")
        ],
        exclude: testTargetExcludes("GroveChatTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveConsent
    .target(
        name: "GroveConsent",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveViews"),
            .target(name: "GroveOnboarding"),
            .target(name: "GrovePersonalInfo"),
            .product(name: "TPPDF", package: "TPPDF"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ],
        exclude: targetExcludes("GroveConsent"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveConsentTests",
        dependencies: [
            .target(name: "GroveConsent"),
            .target(name: "GroveFoundation"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("GroveConsentTests", additional: ["UITests"]),
        resources: [
            .process("Resources"),
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveContact
    .target(
        name: "GroveContact",
        dependencies: [
            .target(name: "GroveViews"),
            .target(name: "GrovePersonalInfo")
        ],
        exclude: targetExcludes("GroveContact"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings + [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveContactTests",
        dependencies: [
            .target(name: "GroveContact")
        ],
        exclude: testTargetExcludes("GroveContactTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings + [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveDevices
    .target(
        name: "GroveDevices",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveBluetooth"),
            .target(name: "GroveBluetoothServices"),
            .target(name: "GroveViews"),
            .target(name: "Grove")
        ],
        exclude: targetExcludes("GroveDevices"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveDevicesUI",
        dependencies: [
            .target(name: "GroveDevices"),
            .target(name: "GroveViews"),
            .target(name: "GroveValidation"),
            .target(name: "GroveBluetooth")
        ],
        exclude: targetExcludes("GroveDevicesUI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveOmron",
        dependencies: [
            .target(name: "GroveDevices"),
            .target(name: "GroveBluetooth"),
            .target(name: "GroveBluetoothServices")
        ],
        exclude: targetExcludes("GroveOmron"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveDevicesTests",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveDevices"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveTesting"),
            .target(name: "GroveBluetooth"),
            .target(name: "GroveBluetoothServices")
        ],
        exclude: testTargetExcludes("GroveDevicesTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveOmronTests",
        dependencies: [
            .target(name: "GroveOmron"),
            .target(name: "GroveBluetooth"),
            .target(name: "ByteCodingTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveFHIR
    .target(
        name: "GroveFHIR",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .product(name: "ModelsDSTU2", package: "FHIRModels", condition: fhirModelsCondition)
        ],
        exclude: targetExcludes("GroveFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFHIRMockPatients",
        dependencies: [
            .target(name: "GroveFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition)
        ],
        exclude: targetExcludes("GroveFHIRMockPatients"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveFHIRTests",
        dependencies: [
            .target(name: "GroveFHIR"),
            "GroveHealthKitFHIR"
        ],
        exclude: testTargetExcludes("GroveFHIRTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveFileFormats
    .target(
        name: "GroveFileFormats",
        exclude: targetExcludes("GroveFileFormats"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "EDFFormat",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "GroveNumerics")
        ],
        exclude: targetExcludes("EDFFormat"),
        swiftSettings: defaultSwiftSettings + [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "EDFFormatTests",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "EDFFormat")
        ],
        swiftSettings: defaultSwiftSettings + [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveFirebase
    .target(
        name: "GroveFirebase",
        exclude: targetExcludes("GroveFirebase"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFirebaseAccount",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveFirebaseConfiguration"),
            .target(name: "GroveFoundation"),
            .target(name: "Grove"),
            .target(name: "GroveValidation"),
            .target(name: "GroveAccount"),
            .target(name: "GroveLocalStorage"),
            .target(name: "GroveKeychainStorage"),
            .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
        ],
        exclude: targetExcludes("GroveFirebaseAccount"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFirebaseConfiguration",
        dependencies: [
            .target(name: "Grove"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
        ],
        exclude: targetExcludes("GroveFirebaseConfiguration"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFirestore",
        dependencies: [
            .target(name: "GroveFirebaseConfiguration"),
            .target(name: "Grove"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            .product(name: "Atomics", package: "swift-atomics")
        ],
        exclude: targetExcludes("GroveFirestore"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFirebaseStorage",
        dependencies: [
            .target(name: "GroveFirebaseConfiguration"),
            .target(name: "Grove"),
            .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
        ],
        exclude: targetExcludes("GroveFirebaseStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFirebaseAccountStorage",
        dependencies: [
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            .target(name: "Grove"),
            .target(name: "GroveAccount"),
            .target(name: "GroveFirestore")
        ],
        exclude: targetExcludes("GroveFirebaseAccountStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveFirebaseTests",
        dependencies: [
            .target(name: "GroveFirebaseAccount"),
            .target(name: "GroveFirebaseConfiguration"),
            .target(name: "GroveFirestore")
        ],
        exclude: testTargetExcludes("GroveFirebaseTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: ThreadLocal
    .macro(
        name: "ThreadLocalMacros",
        dependencies: [
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "ThreadLocal",
        dependencies: [
            .target(name: "ThreadLocalMacros")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "ThreadLocalTests",
        dependencies: [
            .target(name: "ThreadLocal"),
            .target(name: "ThreadLocalMacros"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveFoundation
    .systemLibrary(
        name: "GroveCZlib",
        path: "Sources/CZlib",
        pkgConfig: "zlib",
        providers: [.apt(["zlib1g-dev"])]
    ),
    .target(
        name: "GroveLegacyIdentifiers",
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFoundation",
        dependencies: [
            .target(name: "GroveFoundationObjC"),
            .target(name: "GroveCZlib", condition: .when(platforms: [.linux])),
            .product(name: "libzstd", package: "zstd"),
            .product(name: "Atomics", package: "swift-atomics"),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .target(name: "RuntimeAssertions"),
            .product(name: "Logging", package: "swift-log"),
            .target(name: "ThreadLocal")
        ],
        exclude: targetExcludes("GroveFoundation", additional: ["Dockerfile"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveFoundationObjC",
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLocalization",
        dependencies: [
            .target(name: "GroveFoundation"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        exclude: targetExcludes("GroveLocalization"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveFoundationTests",
        dependencies: [
            .target(name: "GroveFoundation"),
            .target(name: "GroveLegacyIdentifiers")
        ],
        exclude: testTargetExcludes("GroveFoundationTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveLocalizationTests",
        dependencies: [
            .target(name: "GroveLocalization"),
            .target(name: "GroveFoundation")
        ],
        exclude: testTargetExcludes("GroveLocalizationTests"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveHealthKit
    .target(
        name: "GroveHealthKit",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveLocalStorage", condition: .when(platforms: [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS])),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
        ],
        exclude: targetExcludes("GroveHealthKit", additional: [
            "Sample Types/SampleTypeDefs.py",
            "Sample Types/SampleTypes.swift.gyb",
            "codecov.yml"
        ]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveHealthKitBulkExport",
        dependencies: [
            .target(name: "GroveHealthKit"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveLocalStorage", condition: .when(platforms: [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS]))
        ],
        exclude: targetExcludes("GroveHealthKitBulkExport"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveHealthKitUI",
        dependencies: [
            .target(name: "GroveHealthKit"),
            .target(name: "GroveFoundation")
        ],
        exclude: targetExcludes("GroveHealthKitUI"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveHealthKitTests",
        dependencies: [
            .target(name: "XCTGrove"),
            .target(name: "GroveHealthKit"),
            .target(name: "GroveHealthKitBulkExport"),
            .target(name: "GroveHealthKitUI"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("GroveHealthKitTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveLLM
    .target(
        name: "GroveLLM",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveLocalization"),
            .target(name: "GroveChat", condition: applePlatformsOnly),
            .target(name: "GroveViews", condition: applePlatformsOnly)
        ],
        exclude: targetExcludes("GroveLLM"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMLocal",
        dependencies: [
            .target(name: "GroveLLM"),
            .target(name: "GroveFoundation"),
            .target(name: "Grove"),
            .product(name: "MLX", package: "mlx-swift", condition: .when(traits: [mlxTrait])),
            .product(name: "MLXRandom", package: "mlx-swift", condition: .when(traits: [mlxTrait])),
            .product(name: "Transformers", package: "swift-transformers", condition: .when(traits: [mlxTrait])),
            .product(name: "MLXLLM", package: "mlx-swift-examples", condition: .when(traits: [mlxTrait]))
        ],
        exclude: targetExcludes("GroveLLMLocal"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMLocalDownload",
        dependencies: [
            .target(name: "GroveOnboarding"),
            .target(name: "GroveViews"),
            .target(name: "GroveLLMLocal"),
            .product(name: "MLXLLM", package: "mlx-swift-examples", condition: .when(traits: [mlxTrait]))
        ],
        exclude: targetExcludes("GroveLLMLocalDownload"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMOpenAI",
        dependencies: [
            .target(name: "GroveLLM"),
            .target(name: "GroveLocalization"),
            .target(name: "GeneratedOpenAIClient"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .target(name: "GroveFoundation"),
            .target(name: "Grove"),
            .target(name: "GroveChat", condition: applePlatformsOnly),
            .target(name: "GroveKeychainStorage", condition: applePlatformsOnly),
            .target(name: "GroveOnboarding", condition: applePlatformsOnly)
        ],
        exclude: targetExcludes("GroveLLMOpenAI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMOpenAIRealtime",
        dependencies: [
            .target(name: "GroveLLM"),
            .target(name: "GroveLLMOpenAI"),
            .target(name: "GeneratedOpenAIClient"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .target(name: "GroveFoundation"),
            .target(name: "Grove"),
            .target(name: "GroveChat"),
            .target(name: "GroveKeychainStorage"),
            .target(name: "GroveOnboarding")
        ],
        exclude: targetExcludes("GroveLLMOpenAIRealtime"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMAnthropic",
        dependencies: [
            .target(name: "GroveLLMOpenAI"),
            .target(name: "GroveKeychainStorage", condition: applePlatformsOnly)
        ],
        exclude: targetExcludes("GroveLLMAnthropic"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMGemini",
        dependencies: [
            .target(name: "GroveLLMOpenAI"),
            .target(name: "GroveKeychainStorage", condition: applePlatformsOnly)
        ],
        exclude: targetExcludes("GroveLLMGemini"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLLMFoundationModels",
        dependencies: [
            .target(name: "GroveLLM")
        ],
        exclude: targetExcludes("GroveLLMFoundationModels"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GeneratedOpenAIClient",
        dependencies: [
            .target(name: "GroveLLM"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveKeychainStorage", condition: applePlatformsOnly),
            .target(name: "GroveOnboarding", condition: applePlatformsOnly),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
        ],
        exclude: targetExcludes("GeneratedOpenAIClient", additional: [
            "package.json",
            "preprocess-openapi-spec.js",
            "package-lock.json"
        ]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")] + defaultPlugins
    ),
    .testTarget(
        name: "GroveLLMTests",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveTesting"),
            .target(name: "GroveChat"),
            .target(name: "GroveLLM"),
            .target(name: "GroveLLMFoundationModels"),
            .target(name: "GroveLLMOpenAI")
        ],
        exclude: testTargetExcludes("GroveLLMTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveLicense
    .target(
        name: "GroveLicense",
        dependencies: [
            .product(name: "SwiftPackageList", package: "swift-package-list")
        ],
        exclude: targetExcludes("GroveLicense"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveLicenseTests",
        dependencies: [
            .target(name: "GroveLicense"),
            .target(name: "Grove")
        ],
        exclude: testTargetExcludes("GroveLicenseTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveLocation
    .target(
        name: "GroveLocation",
        dependencies: [
            .target(name: "Grove")
        ],
        exclude: targetExcludes("GroveLocation"),
        swiftSettings: defaultSwiftSettings + [
            .swiftLanguageMode(.v5) // TODO???
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveLocationTests",
        dependencies: [
            .target(name: "GroveLocation")
        ],
        exclude: testTargetExcludes("GroveLocationTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings + [
            .swiftLanguageMode(.v5) // TODO???
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveNetworking
    .target(
        name: "GroveNetworking",
        exclude: targetExcludes("GroveNetworking"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "ByteCoding",
        dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio")
        ],
        exclude: targetExcludes("ByteCoding"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveNumerics",
        dependencies: [
            .target(name: "ByteCoding"),
            .product(name: "NIOCore", package: "swift-nio")
        ],
        exclude: targetExcludes("GroveNumerics"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "ByteCodingTesting",
        dependencies: [
            .target(name: "ByteCoding")
        ],
        exclude: targetExcludes("ByteCodingTesting"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTByteCoding",
        dependencies: [
            .target(name: "ByteCoding")
        ],
        exclude: targetExcludes("XCTByteCoding"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "ByteCodingTests",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "ByteCodingTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveNumericsTests",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "GroveNumerics"),
            .target(name: "ByteCodingTesting"),
            .product(name: "RealModule", package: "swift-numerics")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveNotifications
    .target(
        name: "GroveNotifications",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveFoundation"),
            .target(name: "Grove")
        ],
        exclude: targetExcludes("GroveNotifications"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTGroveNotifications",
        dependencies: [
            .target(name: "GroveNotifications")
        ],
        exclude: targetExcludes("XCTGroveNotifications"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTGroveNotificationsUI",
        dependencies: [
            .target(name: "GroveNotifications"),
            .target(name: "GroveViews")
        ],
        exclude: targetExcludes("XCTGroveNotificationsUI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveNotificationsTests",
        dependencies: [
            .target(name: "GroveNotifications"),
            .target(name: "Grove"),
            .target(name: "XCTGrove")
        ],
        exclude: testTargetExcludes("GroveNotificationsTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveOnboarding
    .target(
        name: "GroveOnboarding",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveViews")
        ],
        exclude: targetExcludes("GroveOnboarding"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveOnboardingTests",
        dependencies: [
            .target(name: "GroveOnboarding")
        ],
        exclude: testTargetExcludes("GroveOnboardingTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveQuestionnaire
    .target(
        name: "GroveQuestionnaire",
        dependencies: [
            .target(name: "GroveQuestionnaireLegacy", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .target(name: "GroveViews"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            .product(name: "Numerics", package: "swift-numerics")
        ],
        exclude: targetExcludes("GroveQuestionnaire"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveQuestionnaireCatalog",
        dependencies: [
            .target(name: "GroveQuestionnaire")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveQuestionnaireFHIR",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveQuestionnaire"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .target(name: "GroveFoundation")
        ],
        exclude: targetExcludes("GroveQuestionnaireFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveQuestionnaireLegacy",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .product(name: "ResearchKit", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .product(name: "ResearchKitSwiftUI", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .target(name: "ResearchKitOnFHIR", condition: .when(platforms: [.iOS], traits: [researchKitTrait]))
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTGroveQuestionnaire",
        dependencies: [
            .target(name: "XCTestExtensions")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveQuestionnaireTests",
        dependencies: [
            .target(name: "GroveQuestionnaire"),
            .target(name: "GroveQuestionnaireCatalog"),
            .target(name: "GroveQuestionnaireFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRQuestionnaires")
        ],
        exclude: testTargetExcludes("GroveQuestionnaireTests", additional: ["UITests"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveScheduler
    .target(
        name: "GroveScheduler",
        dependencies: { () -> [Target.Dependency] in
            var deps: [Target.Dependency] = [
                .target(name: "Grove"),
                .target(name: "GroveFoundation"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .target(name: "RuntimeAssertions")
            ]
            #if canImport(Darwin)
            deps += [
                .target(name: "GroveSchedulerMacros"),
                .target(name: "GroveViews"),
                .target(name: "GroveNotifications"),
                .target(name: "GroveLocalStorage"),
                .product(name: "SQLite", package: "SQLite.swift")
            ]
            #endif
            return deps
        }(),
        exclude: targetExcludes("GroveScheduler"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveSensorKit
    .target(
        name: "GroveSensorKit",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "Grove"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveLocalStorage")
        ],
        exclude: targetExcludes("GroveSensorKit"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveSensorKitTests",
        dependencies: [
            .target(name: "GroveSensorKit")
        ],
        exclude: testTargetExcludes("GroveSensorKitTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveSpeech
    .target(
        name: "GroveSpeech",
        exclude: targetExcludes("GroveSpeech"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveSpeechRecognizer",
        dependencies: [
            .target(name: "Grove")
        ],
        exclude: targetExcludes("GroveSpeechRecognizer"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveSpeechSynthesizer",
        dependencies: [
            .target(name: "Grove")
        ],
        exclude: targetExcludes("GroveSpeechSynthesizer"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveSpeechTests",
        dependencies: [
            .target(name: "GroveSpeechRecognizer"),
            .target(name: "GroveSpeechSynthesizer")
        ],
        exclude: testTargetExcludes("GroveSpeechTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveStorage
    .target(
        name: "GroveStorage",
        exclude: targetExcludes("GroveStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveKeychainStorage",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "RuntimeAssertions")
        ],
        exclude: targetExcludes("GroveKeychainStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveLocalStorage",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "Grove"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveKeychainStorage")
        ],
        exclude: targetExcludes("GroveLocalStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveStorageTests",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveLocalStorage"),
            .target(name: "XCTGrove")
        ],
        exclude: testTargetExcludes("GroveStorageTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveStudy
    .target(
        name: "GroveStudyDefinition",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "GroveHealthKit"),
            .target(name: "GroveHealthKitBulkExport"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveLocalization"),
            .target(name: "GroveScheduler"),
            .product(name: "DequeModule", package: "swift-collections"),
            .product(name: "Logging", package: "swift-log")
        ],
        exclude: targetExcludes("GroveStudyDefinition"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveStudyTests",
        dependencies: { () -> [Target.Dependency] in
            var deps: [Target.Dependency] = [
                .target(name: "GroveStudyDefinition"),
                .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition)
            ]
            #if canImport(Darwin)
            deps += [
                .target(name: "GroveStudy"),
                .target(name: "GroveTesting")
            ]
            #endif
            return deps
        }(),
        exclude: testTargetExcludes("GroveStudyTests", additional: ["UITests"]),
        resources: [
            .process("Resources/questionnaires"),
            .copy("Resources/assets")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveViews
    .target(
        name: "GroveViews",
        dependencies: [
            .target(name: "Grove"),
            .target(name: "GroveFoundation"),
            .target(name: "GroveLocalization"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ],
        exclude: targetExcludes("GroveViews"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GrovePersonalInfo",
        dependencies: [
            .target(name: "GroveViews")
        ],
        exclude: targetExcludes("GrovePersonalInfo"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GroveValidation",
        dependencies: [
            .target(name: "GroveViews"),
            .target(name: "GroveFoundation"),
            .product(name: "OrderedCollections", package: "swift-collections")
        ],
        exclude: targetExcludes("GroveValidation"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "GroveViewsTests",
        dependencies: [
            .target(name: "GroveViews"),
            .target(name: "GroveValidation"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("GroveViewsTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: XCTHealthKit
    .target(
        name: "XCTHealthKit",
        exclude: targetExcludes("XCTHealthKit"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "XCTHealthKitTests",
        dependencies: [
            .target(name: "XCTHealthKit")
        ],
        exclude: testTargetExcludes("XCTHealthKitTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: RuntimeAssertions
    .target(
        name: "RuntimeAssertions",
        exclude: targetExcludes("RuntimeAssertions"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "RuntimeAssertionsTesting",
        dependencies: [
            .target(name: "RuntimeAssertions")
        ],
        exclude: targetExcludes("RuntimeAssertionsTesting"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "RuntimeAssertionsTests",
        dependencies: [
            .target(name: "RuntimeAssertions"),
            .target(name: "RuntimeAssertionsTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: XCTestExtensions
    .target(
        name: "XCTestApp",
        exclude: targetExcludes("XCTestApp"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTestExtensions",
        exclude: targetExcludes("XCTestExtensions"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "XCTestExtensionsTests",
        dependencies: [
            .target(name: "XCTestExtensions")
        ],
        exclude: testTargetExcludes("XCTestExtensionsTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
]

#if canImport(Darwin)
targets += [
    // MARK: GroveScheduler
    .macro(
        name: "GroveSchedulerMacros",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveScheduler
    .target(
        name: "GroveSchedulerUI",
        dependencies: [
            .target(name: "GroveScheduler"),
            .target(name: "GroveViews")
        ],
        exclude: targetExcludes("GroveSchedulerUI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveScheduler
    .testTarget(
        name: "GroveSchedulerTests",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveScheduler"),
            .target(name: "GroveSchedulerMacros"),
            .target(name: "XCTGrove"),
            .target(name: "GroveLocalStorage"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        exclude: testTargetExcludes("GroveSchedulerTests", additional: ["UITests"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveScheduler
    .testTarget(
        name: "GroveSchedulerUITests",
        dependencies: [
            .target(name: "GroveScheduler"),
            .target(name: "GroveSchedulerUI"),
            .target(name: "GroveTesting"),
            .target(name: "XCTGrove"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveStudy
    .target(
        name: "GroveStudy",
        dependencies: [
            .target(name: "GroveLegacyIdentifiers"),
            .target(name: "GroveStudyDefinition"),
            .target(name: "Grove"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "GroveHealthKit"),
            .target(name: "GroveLocalStorage"),
            .target(name: "GroveScheduler"),
            .target(name: "GroveSchedulerUI"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        exclude: targetExcludes("GroveStudy"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
]
#endif

#if canImport(HealthKit)
targets += [
    // MARK: GroveHealthKit
    .executableTarget(
        name: "LocalizationsProcessor",
        dependencies: [
            .target(name: "GroveHealthKit"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: GroveHealthKit
    .executableTarget(
        name: "Codegen",
        dependencies: [
            .target(name: "GroveHealthKit"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        exclude: targetExcludes("Codegen", additional: ["HKTypeIdentifierDefs+Linux.swift.gyb"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
]
#endif

let package = Package(
    name: "Grove",
    defaultLocalization: "en",
    platforms: packagePlatforms,
    products: products,
    traits: [
        .default(enabledTraits: defaultEnabledTraits),
        .trait(
            name: textualTrait,
            description: "Enable targets that depend on Textual for rich chat message rendering."
        ),
        .trait(
            name: mlxTrait,
            description: "Enable local LLM targets that depend on MLX and swift-transformers."
        ),
        .trait(
            name: researchKitTrait,
            description: "Enable legacy questionnaire targets that depend on ResearchKit."
        )
    ],
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v6]
)
