// swift-tools-version:6.3
//
// This source file is part of the Stanford Spezi open-source project
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
let isLoweredDeploymentTargetEnabled = Context.environment["SPEZI_LOWERED_DEPLOYMENT_TARGETS"] == "1"

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
let optionalPackageTraits = [textualTrait, mlxTrait, researchKitTrait]

let defaultEnabledTraits: Set<String> = Context.environment["SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS"] == "1"
    ? Set(optionalPackageTraits)
    : []
// Compile/test builds can exclude DocC catalogs to avoid SwiftPM unhandled-file warnings.
// Documentation builds keep them included so DocC can resolve articles and assets.
let excludeDocCCatalogs = Context.environment["SPEZI_EXCLUDE_DOCC_CATALOGS"] == "1"

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
    .package(url: "https://github.com/SchmiedmayerLab/FHIRModels.git", exact: "0.9.3"),
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
    // MARK: Spezi
    .library(name: "Spezi", targets: ["Spezi"]),
    .library(name: "SpeziTesting", targets: ["SpeziTesting"]),
    .library(name: "XCTSpezi", targets: ["XCTSpezi"]),
    // MARK: SpeziAccessGuard
    .library(name: "SpeziAccessGuard", targets: ["SpeziAccessGuard"]),
    // MARK: SpeziAccount
    .library(name: "SpeziAccount", targets: ["SpeziAccount"]),
    .library(name: "XCTSpeziAccount", targets: ["XCTSpeziAccount"]),
    .library(name: "SpeziAccountPhoneNumbers", targets: ["SpeziAccountPhoneNumbers"]),
    // MARK: SpeziBluetooth
    .library(name: "SpeziBluetoothServices", targets: ["SpeziBluetoothServices"]),
    .library(name: "SpeziBluetooth", targets: ["SpeziBluetooth"]),
    // MARK: SpeziChat
    .library(name: "SpeziChat", targets: ["SpeziChat"]),
    // MARK: SpeziConsent
    .library(name: "SpeziConsent", targets: ["SpeziConsent"]),
    // MARK: SpeziContact
    .library(name: "SpeziContact", targets: ["SpeziContact"]),
    // MARK: SpeziDevices
    .library(name: "SpeziDevices", targets: ["SpeziDevices"]),
    .library(name: "SpeziDevicesUI", targets: ["SpeziDevicesUI"]),
    .library(name: "SpeziOmron", targets: ["SpeziOmron"]),
    // MARK: SpeziFHIR
    .library(name: "SpeziFHIR", targets: ["SpeziFHIR"]),
    .library(name: "SpeziFHIRMockPatients", targets: ["SpeziFHIRMockPatients"]),
    // MARK: SpeziFileFormats
    .library(name: "EDFFormat", targets: ["EDFFormat"]),
    // MARK: SpeziFirebase
    .library(name: "SpeziFirebaseAccount", targets: ["SpeziFirebaseAccount"]),
    .library(name: "SpeziFirebaseConfiguration", targets: ["SpeziFirebaseConfiguration"]),
    .library(name: "SpeziFirestore", targets: ["SpeziFirestore"]),
    .library(name: "SpeziFirebaseStorage", targets: ["SpeziFirebaseStorage"]),
    .library(name: "SpeziFirebaseAccountStorage", targets: ["SpeziFirebaseAccountStorage"]),
    // MARK: SpeziFoundation
    .library(name: "SpeziFoundation", targets: ["SpeziFoundation"]),
    .library(name: "SpeziLocalization", targets: ["SpeziLocalization"]),
    .library(name: "ThreadLocal", targets: ["ThreadLocal"]),
    // MARK: SpeziHealthKit
    .library(name: "SpeziHealthKit", targets: ["SpeziHealthKit"]),
    .library(name: "SpeziHealthKitBulkExport", targets: ["SpeziHealthKitBulkExport"]),
    .library(name: "SpeziHealthKitUI", targets: ["SpeziHealthKitUI"]),
    .library(name: "SpeziHealthKitFHIR", targets: ["SpeziHealthKitFHIR"]),
    // MARK: SpeziLLM
    .library(name: "SpeziLLM", targets: ["SpeziLLM"]),
    .library(name: "SpeziLLMLocal", targets: ["SpeziLLMLocal"]),
    .library(name: "SpeziLLMLocalDownload", targets: ["SpeziLLMLocalDownload"]),
    .library(name: "SpeziLLMOpenAI", targets: ["SpeziLLMOpenAI"]),
    .library(name: "SpeziLLMFog", targets: ["SpeziLLMFog"]),
    .library(name: "SpeziLLMOpenAIRealtime", targets: ["SpeziLLMOpenAIRealtime"]),
    .library(name: "SpeziLLMAnthropic", targets: ["SpeziLLMAnthropic"]),
    .library(name: "SpeziLLMGemini", targets: ["SpeziLLMGemini"]),
    // MARK: SpeziLicense
    .library(name: "SpeziLicense", targets: ["SpeziLicense"]),
    // MARK: SpeziLocation
    .library(name: "SpeziLocation", targets: ["SpeziLocation"]),
    // MARK: SpeziNetworking
    .library(name: "ByteCoding", targets: ["ByteCoding"]),
    .library(name: "SpeziNumerics", targets: ["SpeziNumerics"]),
    .library(name: "XCTByteCoding", targets: ["XCTByteCoding"]),
    .library(name: "ByteCodingTesting", targets: ["ByteCodingTesting"]),
    // MARK: SpeziNotifications
    .library(name: "SpeziNotifications", targets: ["SpeziNotifications"]),
    .library(name: "XCTSpeziNotifications", targets: ["XCTSpeziNotifications"]),
    .library(name: "XCTSpeziNotificationsUI", targets: ["XCTSpeziNotificationsUI"]),
    // MARK: SpeziOnboarding
    .library(name: "SpeziOnboarding", targets: ["SpeziOnboarding"]),
    // MARK: SpeziQuestionnaire
    .library(name: "SpeziQuestionnaire", targets: ["SpeziQuestionnaire"]),
    .library(name: "SpeziQuestionnaireCatalog", targets: ["SpeziQuestionnaireCatalog"]),
    .library(name: "SpeziQuestionnaireFHIR", targets: ["SpeziQuestionnaireFHIR"]),
    .library(name: "SpeziQuestionnaireLegacy", targets: ["SpeziQuestionnaireLegacy"]),
    .library(name: "XCTSpeziQuestionnaire", targets: ["XCTSpeziQuestionnaire"]),
    // MARK: SpeziScheduler
    .library(name: "SpeziScheduler", targets: ["SpeziScheduler"]),
    // MARK: SpeziSensorKit
    .library(name: "SpeziSensorKit", targets: ["SpeziSensorKit"]),
    // MARK: SpeziSpeech
    .library(name: "SpeziSpeechRecognizer", targets: ["SpeziSpeechRecognizer"]),
    .library(name: "SpeziSpeechSynthesizer", targets: ["SpeziSpeechSynthesizer"]),
    // MARK: SpeziStorage
    .library(name: "SpeziLocalStorage", targets: ["SpeziLocalStorage"]),
    .library(name: "SpeziKeychainStorage", targets: ["SpeziKeychainStorage"]),
    // MARK: SpeziStudy
    .library(name: "SpeziStudyDefinition", targets: ["SpeziStudyDefinition"]),
    // MARK: SpeziViews
    .library(name: "SpeziViews", targets: ["SpeziViews"]),
    .library(name: "SpeziPersonalInfo", targets: ["SpeziPersonalInfo"]),
    .library(name: "SpeziValidation", targets: ["SpeziValidation"]),
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
    // MARK: SpeziScheduler
    .library(name: "SpeziSchedulerUI", targets: ["SpeziSchedulerUI"]),
    // MARK: SpeziStudy
    .library(name: "SpeziStudy", targets: ["SpeziStudy"])
]
#endif


var targets: [Target] = [
    // MARK: FHIRModelsExtensions
    .target(
        name: "FHIRModelsExtensions",
        dependencies: [
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
    // MARK: SpeziHealthKitFHIR
    .macro(
        name: "SpeziHealthKitFHIRMacrosImpl",
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
        name: "SpeziHealthKitFHIRMacros",
        dependencies: [
            .target(name: "SpeziHealthKitFHIRMacrosImpl")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziHealthKitFHIR",
        dependencies: [
            .target(name: "SpeziHealthKitFHIRMacros"),
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .product(name: "ModelsDSTU2", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions")
        ],
        exclude: targetExcludes("SpeziHealthKitFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziHealthKitFHIRTests",
        dependencies: [
            .target(name: "SpeziHealthKitFHIR"),
            .target(name: "SpeziFoundation")
        ],
        exclude: testTargetExcludes("SpeziHealthKitFHIRTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziHealthKitFHIRMacrosTests",
        dependencies: [
            .target(name: "SpeziHealthKitFHIRMacros"),
            .target(name: "SpeziHealthKitFHIRMacrosImpl"),
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
    // MARK: Spezi
    .target(
        name: "Spezi",
        dependencies: [
            .target(name: "SpeziFoundation"),
            .target(name: "RuntimeAssertions"),
            .product(name: "OrderedCollections", package: "swift-collections")
        ],
        exclude: targetExcludes("Spezi"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziTesting",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: targetExcludes("SpeziTesting"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpezi",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziTests",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziTesting"),
            .product(name: "TestingExpectation", package: "swift-testing-expectation")
        ],
        exclude: testTargetExcludes("SpeziTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings + [
            .define("DEBUG", .when(configuration: .debug))
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziAccessGuard
    .target(
        name: "SpeziAccessGuard",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziKeychainStorage"),
            .target(name: "SpeziViews"),
            .target(name: "SpeziFoundation")
        ],
        exclude: targetExcludes("SpeziAccessGuard"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziAccessGuardTests",
        dependencies: [
            .target(name: "SpeziAccessGuard"),
            .target(name: "SpeziTesting"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("SpeziAccessGuardTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziAccount
    .macro(
        name: "SpeziAccountMacros",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziAccount",
        dependencies: [
            .target(name: "SpeziFoundation"),
            .target(name: "Spezi"),
            .target(name: "SpeziViews"),
            .target(name: "SpeziPersonalInfo"),
            .target(name: "SpeziValidation"),
            .target(name: "SpeziLocalStorage"),
            .target(name: "RuntimeAssertions"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "Atomics", package: "swift-atomics"),
            .target(name: "SpeziAccountMacros")
        ],
        exclude: targetExcludes("SpeziAccount"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziAccount",
        dependencies: [
            .target(name: "SpeziAccount"),
            .target(name: "XCTestExtensions")
        ],
        exclude: targetExcludes("XCTSpeziAccount"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziAccountPhoneNumbers",
        dependencies: [
            .target(name: "SpeziAccount"),
            .product(name: "PhoneNumberKit", package: "PhoneNumberKit")
        ],
        exclude: targetExcludes("SpeziAccountPhoneNumbers"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziAccountTests",
        dependencies: [
            .target(name: "SpeziAccount"),
            .target(name: "SpeziAccountPhoneNumbers"),
            .target(name: "Spezi"),
            .target(name: "SpeziTesting"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("SpeziAccountTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziAccountMacrosTests",
        dependencies: [
            .target(name: "SpeziAccountMacros"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziBluetooth
    .target(
        name: "SpeziBluetooth",
        dependencies: [
            .target(name: "Spezi"),
            .product(name: "NIOCore", package: "swift-nio"),
            .target(name: "SpeziViews"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .target(name: "SpeziFoundation"),
            .target(name: "ByteCoding"),
            .product(name: "Atomics", package: "swift-atomics")
        ],
        exclude: targetExcludes("SpeziBluetooth", additional: ["bin"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziBluetoothServices",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "ByteCoding"),
            .target(name: "SpeziNumerics")
        ],
        exclude: targetExcludes("SpeziBluetoothServices"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .executableTarget(
        name: "TestPeripheral",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices"),
            .target(name: "ByteCoding")
        ],
        exclude: targetExcludes("TestPeripheral"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziBluetoothTests",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices")
        ],
        exclude: testTargetExcludes("SpeziBluetoothTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziBluetoothServicesTests",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices"),
            .product(name: "NIOCore", package: "swift-nio"),
            .target(name: "ByteCodingTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziChat
    .target(
        name: "SpeziChat",
        dependencies: [
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziSpeechRecognizer"),
            .target(name: "SpeziSpeechSynthesizer"),
            .target(name: "SpeziViews"),
            .product(name: "Textual", package: "textual", condition: .when(traits: [textualTrait]))
        ],
        exclude: targetExcludes("SpeziChat"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziChatTests",
        dependencies: [
            .target(name: "SpeziChat")
        ],
        exclude: testTargetExcludes("SpeziChatTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziConsent
    .target(
        name: "SpeziConsent",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziViews"),
            .target(name: "SpeziOnboarding"),
            .target(name: "SpeziPersonalInfo"),
            .product(name: "TPPDF", package: "TPPDF"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ],
        exclude: targetExcludes("SpeziConsent"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziConsentTests",
        dependencies: [
            .target(name: "SpeziConsent"),
            .target(name: "SpeziFoundation"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("SpeziConsentTests", additional: ["UITests"]),
        resources: [
            .process("Resources"),
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziContact
    .target(
        name: "SpeziContact",
        dependencies: [
            .target(name: "SpeziViews"),
            .target(name: "SpeziPersonalInfo")
        ],
        exclude: targetExcludes("SpeziContact"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings + [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziContactTests",
        dependencies: [
            .target(name: "SpeziContact")
        ],
        exclude: testTargetExcludes("SpeziContactTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings + [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziDevices
    .target(
        name: "SpeziDevices",
        dependencies: [
            .product(name: "OrderedCollections", package: "swift-collections"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices"),
            .target(name: "SpeziViews"),
            .target(name: "Spezi")
        ],
        exclude: targetExcludes("SpeziDevices"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziDevicesUI",
        dependencies: [
            .target(name: "SpeziDevices"),
            .target(name: "SpeziViews"),
            .target(name: "SpeziValidation"),
            .target(name: "SpeziBluetooth")
        ],
        exclude: targetExcludes("SpeziDevicesUI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziOmron",
        dependencies: [
            .target(name: "SpeziDevices"),
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices")
        ],
        exclude: targetExcludes("SpeziOmron"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziDevicesTests",
        dependencies: [
            .target(name: "SpeziDevices"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziTesting"),
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices")
        ],
        exclude: testTargetExcludes("SpeziDevicesTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziOmronTests",
        dependencies: [
            .target(name: "SpeziOmron"),
            .target(name: "SpeziBluetooth"),
            .target(name: "ByteCodingTesting")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziFHIR
    .target(
        name: "SpeziFHIR",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .product(name: "ModelsDSTU2", package: "FHIRModels", condition: fhirModelsCondition)
        ],
        exclude: targetExcludes("SpeziFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFHIRMockPatients",
        dependencies: [
            .target(name: "SpeziFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition)
        ],
        exclude: targetExcludes("SpeziFHIRMockPatients"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziFHIRTests",
        dependencies: [
            .target(name: "SpeziFHIR"),
            "SpeziHealthKitFHIR"
        ],
        exclude: testTargetExcludes("SpeziFHIRTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziFileFormats
    .target(
        name: "SpeziFileFormats",
        exclude: targetExcludes("SpeziFileFormats"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "EDFFormat",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "SpeziNumerics")
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
    // MARK: SpeziFirebase
    .target(
        name: "SpeziFirebase",
        exclude: targetExcludes("SpeziFirebase"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirebaseAccount",
        dependencies: [
            .target(name: "SpeziFirebaseConfiguration"),
            .target(name: "SpeziFoundation"),
            .target(name: "Spezi"),
            .target(name: "SpeziValidation"),
            .target(name: "SpeziAccount"),
            .target(name: "SpeziLocalStorage"),
            .target(name: "SpeziKeychainStorage"),
            .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
        ],
        exclude: targetExcludes("SpeziFirebaseAccount"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirebaseConfiguration",
        dependencies: [
            .target(name: "Spezi"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
        ],
        exclude: targetExcludes("SpeziFirebaseConfiguration"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirestore",
        dependencies: [
            .target(name: "SpeziFirebaseConfiguration"),
            .target(name: "Spezi"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            .product(name: "Atomics", package: "swift-atomics")
        ],
        exclude: targetExcludes("SpeziFirestore"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirebaseStorage",
        dependencies: [
            .target(name: "SpeziFirebaseConfiguration"),
            .target(name: "Spezi"),
            .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
        ],
        exclude: targetExcludes("SpeziFirebaseStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirebaseAccountStorage",
        dependencies: [
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            .target(name: "Spezi"),
            .target(name: "SpeziAccount"),
            .target(name: "SpeziFirestore")
        ],
        exclude: targetExcludes("SpeziFirebaseAccountStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziFirebaseTests",
        dependencies: [
            .target(name: "SpeziFirebaseAccount"),
            .target(name: "SpeziFirebaseConfiguration"),
            .target(name: "SpeziFirestore")
        ],
        exclude: testTargetExcludes("SpeziFirebaseTests", additional: ["UITests"]),
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
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
    // MARK: SpeziFoundation
    .systemLibrary(
        name: "SpeziCZlib",
        path: "Sources/CZlib",
        pkgConfig: "zlib",
        providers: [.apt(["zlib1g-dev"])]
    ),
    .target(
        name: "SpeziFoundation",
        dependencies: [
            .target(name: "SpeziFoundationObjC"),
            .target(name: "SpeziCZlib", condition: .when(platforms: [.linux])),
            .product(name: "libzstd", package: "zstd"),
            .product(name: "Atomics", package: "swift-atomics"),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .target(name: "RuntimeAssertions"),
            .product(name: "Logging", package: "swift-log"),
            .target(name: "ThreadLocal")
        ],
        exclude: targetExcludes("SpeziFoundation", additional: ["Dockerfile"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFoundationObjC",
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLocalization",
        dependencies: [
            .target(name: "SpeziFoundation"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        exclude: targetExcludes("SpeziLocalization"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziFoundationTests",
        dependencies: [
            .target(name: "SpeziFoundation")
        ],
        exclude: testTargetExcludes("SpeziFoundationTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziLocalizationTests",
        dependencies: [
            .target(name: "SpeziLocalization"),
            .target(name: "SpeziFoundation")
        ],
        exclude: testTargetExcludes("SpeziLocalizationTests"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziHealthKit
    .target(
        name: "SpeziHealthKit",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalStorage", condition: .when(platforms: [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS])),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
        ],
        exclude: targetExcludes("SpeziHealthKit", additional: [
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
        name: "SpeziHealthKitBulkExport",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalStorage", condition: .when(platforms: [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS]))
        ],
        exclude: targetExcludes("SpeziHealthKitBulkExport"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziHealthKitUI",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziFoundation")
        ],
        exclude: targetExcludes("SpeziHealthKitUI"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziHealthKitTests",
        dependencies: [
            .target(name: "XCTSpezi"),
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziHealthKitBulkExport"),
            .target(name: "SpeziHealthKitUI"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("SpeziHealthKitTests", additional: ["UITests"]),
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziLLM
    .target(
        name: "SpeziLLM",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziChat"),
            .target(name: "SpeziViews")
        ],
        exclude: targetExcludes("SpeziLLM", additional: ["FogNode"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMLocal",
        dependencies: [
            .target(name: "SpeziLLM"),
            .target(name: "SpeziFoundation"),
            .target(name: "Spezi"),
            .product(name: "MLX", package: "mlx-swift", condition: .when(traits: [mlxTrait])),
            .product(name: "MLXRandom", package: "mlx-swift", condition: .when(traits: [mlxTrait])),
            .product(name: "Transformers", package: "swift-transformers", condition: .when(traits: [mlxTrait])),
            .product(name: "MLXLLM", package: "mlx-swift-examples", condition: .when(traits: [mlxTrait]))
        ],
        exclude: targetExcludes("SpeziLLMLocal"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMLocalDownload",
        dependencies: [
            .target(name: "SpeziOnboarding"),
            .target(name: "SpeziViews"),
            .target(name: "SpeziLLMLocal"),
            .product(name: "MLXLLM", package: "mlx-swift-examples", condition: .when(traits: [mlxTrait]))
        ],
        exclude: targetExcludes("SpeziLLMLocalDownload"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMOpenAI",
        dependencies: [
            .target(name: "SpeziLLM"),
            .target(name: "GeneratedOpenAIClient"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .target(name: "SpeziFoundation"),
            .target(name: "Spezi"),
            .target(name: "SpeziChat"),
            .target(name: "SpeziKeychainStorage"),
            .target(name: "SpeziOnboarding")
        ],
        exclude: targetExcludes("SpeziLLMOpenAI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMOpenAIRealtime",
        dependencies: [
            .target(name: "SpeziLLM"),
            .target(name: "SpeziLLMOpenAI"),
            .target(name: "GeneratedOpenAIClient"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .target(name: "SpeziFoundation"),
            .target(name: "Spezi"),
            .target(name: "SpeziChat"),
            .target(name: "SpeziKeychainStorage"),
            .target(name: "SpeziOnboarding")
        ],
        exclude: targetExcludes("SpeziLLMOpenAIRealtime"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMAnthropic",
        dependencies: [
            .target(name: "SpeziLLMOpenAI"),
            .target(name: "SpeziKeychainStorage")
        ],
        exclude: targetExcludes("SpeziLLMAnthropic"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMGemini",
        dependencies: [
            .target(name: "SpeziLLMOpenAI"),
            .target(name: "SpeziKeychainStorage")
        ],
        exclude: targetExcludes("SpeziLLMGemini"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMFog",
        dependencies: [
            .target(name: "SpeziLLM"),
            .target(name: "GeneratedOpenAIClient"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .target(name: "Spezi"),
            .target(name: "SpeziOnboarding")
        ],
        exclude: targetExcludes("SpeziLLMFog"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "GeneratedOpenAIClient",
        dependencies: [
            .target(name: "SpeziLLM"),
            .target(name: "SpeziKeychainStorage"),
            .target(name: "SpeziOnboarding"),
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
        name: "SpeziLLMTests",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziTesting"),
            .target(name: "SpeziLLM"),
            .target(name: "SpeziLLMOpenAI")
        ],
        exclude: testTargetExcludes("SpeziLLMTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziLicense
    .target(
        name: "SpeziLicense",
        dependencies: [
            .product(name: "SwiftPackageList", package: "swift-package-list")
        ],
        exclude: targetExcludes("SpeziLicense"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziLicenseTests",
        dependencies: [
            .target(name: "SpeziLicense"),
            .target(name: "Spezi")
        ],
        exclude: testTargetExcludes("SpeziLicenseTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziLocation
    .target(
        name: "SpeziLocation",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: targetExcludes("SpeziLocation"),
        swiftSettings: defaultSwiftSettings + [
            .swiftLanguageMode(.v5) // TODO???
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziLocationTests",
        dependencies: [
            .target(name: "SpeziLocation")
        ],
        exclude: testTargetExcludes("SpeziLocationTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings + [
            .swiftLanguageMode(.v5) // TODO???
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziNetworking
    .target(
        name: "SpeziNetworking",
        exclude: targetExcludes("SpeziNetworking"),
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
        name: "SpeziNumerics",
        dependencies: [
            .target(name: "ByteCoding"),
            .product(name: "NIOCore", package: "swift-nio")
        ],
        exclude: targetExcludes("SpeziNumerics"),
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
        name: "SpeziNumericsTests",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "SpeziNumerics"),
            .target(name: "ByteCodingTesting"),
            .product(name: "RealModule", package: "swift-numerics")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziNotifications
    .target(
        name: "SpeziNotifications",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: targetExcludes("SpeziNotifications"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziNotifications",
        dependencies: [
            .target(name: "SpeziNotifications")
        ],
        exclude: targetExcludes("XCTSpeziNotifications"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziNotificationsUI",
        dependencies: [
            .target(name: "SpeziNotifications"),
            .target(name: "SpeziViews")
        ],
        exclude: targetExcludes("XCTSpeziNotificationsUI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziNotificationsTests",
        dependencies: [
            .target(name: "SpeziNotifications"),
            .target(name: "Spezi"),
            .target(name: "XCTSpezi")
        ],
        exclude: testTargetExcludes("SpeziNotificationsTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziOnboarding
    .target(
        name: "SpeziOnboarding",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziViews")
        ],
        exclude: targetExcludes("SpeziOnboarding"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziOnboardingTests",
        dependencies: [
            .target(name: "SpeziOnboarding")
        ],
        exclude: testTargetExcludes("SpeziOnboardingTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziQuestionnaire
    .target(
        name: "SpeziQuestionnaire",
        dependencies: [
            .target(name: "SpeziQuestionnaireLegacy", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .target(name: "SpeziViews"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            .product(name: "Numerics", package: "swift-numerics")
        ],
        exclude: targetExcludes("SpeziQuestionnaire"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziQuestionnaireCatalog",
        dependencies: [
            .target(name: "SpeziQuestionnaire")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziQuestionnaireFHIR",
        dependencies: [
            .target(name: "SpeziQuestionnaire"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .target(name: "SpeziFoundation")
        ],
        exclude: targetExcludes("SpeziQuestionnaireFHIR"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziQuestionnaireLegacy",
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
        name: "XCTSpeziQuestionnaire",
        dependencies: [
            .target(name: "XCTestExtensions")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziQuestionnaireTests",
        dependencies: [
            .target(name: "SpeziQuestionnaire"),
            .target(name: "SpeziQuestionnaireCatalog"),
            .target(name: "SpeziQuestionnaireFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRQuestionnaires")
        ],
        exclude: testTargetExcludes("SpeziQuestionnaireTests", additional: ["UITests"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziScheduler
    .target(
        name: "SpeziScheduler",
        dependencies: { () -> [Target.Dependency] in
            var deps: [Target.Dependency] = [
                .target(name: "Spezi"),
                .target(name: "SpeziFoundation"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .target(name: "RuntimeAssertions")
            ]
            #if canImport(Darwin)
            deps += [
                .target(name: "SpeziSchedulerMacros"),
                .target(name: "SpeziViews"),
                .target(name: "SpeziNotifications"),
                .target(name: "SpeziLocalStorage"),
                .product(name: "SQLite", package: "SQLite.swift")
            ]
            #endif
            return deps
        }(),
        exclude: targetExcludes("SpeziScheduler"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziSensorKit
    .target(
        name: "SpeziSensorKit",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalStorage")
        ],
        exclude: targetExcludes("SpeziSensorKit"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziSensorKitTests",
        dependencies: [
            .target(name: "SpeziSensorKit")
        ],
        exclude: testTargetExcludes("SpeziSensorKitTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziSpeech
    .target(
        name: "SpeziSpeech",
        exclude: targetExcludes("SpeziSpeech"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziSpeechRecognizer",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: targetExcludes("SpeziSpeechRecognizer"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziSpeechSynthesizer",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: targetExcludes("SpeziSpeechSynthesizer"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziSpeechTests",
        dependencies: [
            .target(name: "SpeziSpeechRecognizer"),
            .target(name: "SpeziSpeechSynthesizer")
        ],
        exclude: testTargetExcludes("SpeziSpeechTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziStorage
    .target(
        name: "SpeziStorage",
        exclude: targetExcludes("SpeziStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziKeychainStorage",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "RuntimeAssertions")
        ],
        exclude: targetExcludes("SpeziKeychainStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLocalStorage",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziKeychainStorage")
        ],
        exclude: targetExcludes("SpeziLocalStorage"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziStorageTests",
        dependencies: [
            .target(name: "SpeziLocalStorage"),
            .target(name: "XCTSpezi")
        ],
        exclude: testTargetExcludes("SpeziStorageTests", additional: ["UITests"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziStudy
    .target(
        name: "SpeziStudyDefinition",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziHealthKitBulkExport"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalization"),
            .target(name: "SpeziScheduler"),
            .product(name: "DequeModule", package: "swift-collections"),
            .product(name: "Logging", package: "swift-log")
        ],
        exclude: targetExcludes("SpeziStudyDefinition"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziStudyTests",
        dependencies: { () -> [Target.Dependency] in
            var deps: [Target.Dependency] = [
                .target(name: "SpeziStudyDefinition"),
                .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition)
            ]
            #if canImport(Darwin)
            deps += [
                .target(name: "SpeziStudy"),
                .target(name: "SpeziTesting")
            ]
            #endif
            return deps
        }(),
        exclude: testTargetExcludes("SpeziStudyTests", additional: ["UITests"]),
        resources: [
            .process("Resources/questionnaires"),
            .copy("Resources/assets")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziViews
    .target(
        name: "SpeziViews",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalization"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ],
        exclude: targetExcludes("SpeziViews"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziPersonalInfo",
        dependencies: [
            .target(name: "SpeziViews")
        ],
        exclude: targetExcludes("SpeziPersonalInfo"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziValidation",
        dependencies: [
            .target(name: "SpeziViews"),
            .target(name: "SpeziFoundation"),
            .product(name: "OrderedCollections", package: "swift-collections")
        ],
        exclude: targetExcludes("SpeziValidation"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziViewsTests",
        dependencies: [
            .target(name: "SpeziViews"),
            .target(name: "SpeziValidation"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: testTargetExcludes("SpeziViewsTests", additional: ["UITests"]),
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
    // MARK: SpeziScheduler
    .macro(
        name: "SpeziSchedulerMacros",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziScheduler
    .target(
        name: "SpeziSchedulerUI",
        dependencies: [
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziViews")
        ],
        exclude: targetExcludes("SpeziSchedulerUI"),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziScheduler
    .testTarget(
        name: "SpeziSchedulerTests",
        dependencies: [
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziSchedulerMacros"),
            .target(name: "XCTSpezi"),
            .target(name: "SpeziLocalStorage"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        exclude: testTargetExcludes("SpeziSchedulerTests", additional: ["UITests"]),
        resources: [
            .process("Resources")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziScheduler
    .testTarget(
        name: "SpeziSchedulerUITests",
        dependencies: [
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziSchedulerUI"),
            .target(name: "SpeziTesting"),
            .target(name: "XCTSpezi"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziStudy
    .target(
        name: "SpeziStudy",
        dependencies: [
            .target(name: "SpeziStudyDefinition"),
            .target(name: "Spezi"),
            .product(name: "ModelsR4", package: "FHIRModels", condition: fhirModelsCondition),
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziLocalStorage"),
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziSchedulerUI"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        exclude: targetExcludes("SpeziStudy"),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
]
#endif

#if canImport(HealthKit)
targets += [
    // MARK: SpeziHealthKit
    .executableTarget(
        name: "LocalizationsProcessor",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziHealthKit
    .executableTarget(
        name: "Codegen",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        exclude: targetExcludes("Codegen", additional: ["HKTypeIdentifierDefs+Linux.swift.gyb"]),
        swiftSettings: defaultSwiftSettings,
        plugins: [] + defaultPlugins
    ),
]
#endif

let package = Package(
    name: "Spezi",
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
