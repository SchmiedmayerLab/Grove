// swift-tools-version:6.2

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CompilerPluginSupport
import PackageDescription


// Toggle SwiftLint by setting this to `true`.
let enableSwiftLint = false

var defaultPlugins: [Target.PluginUsage] {
    enableSwiftLint ? [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")] : []
}

let textualTrait = "Textual"
let mlxTrait = "MLX"
let researchKitTrait = "ResearchKit"
let optionalPackageTraits = [textualTrait, mlxTrait, researchKitTrait]

let defaultEnabledTraits: Set<String> = Context.environment["SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS"] == "1"
    ? Set(optionalPackageTraits)
    : []
let packagePlatforms: [SupportedPlatform] = [
    .iOS(.v15),
    .macOS(.v12),
    .watchOS(.v8)
]


var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/antlr/antlr4.git", from: "4.13.1"),
    .package(url: "https://github.com/apple/FHIRModels.git", .upToNextMinor(from: "0.8.0")),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.1.0"),
    .package(url: "https://github.com/marmelroy/PhoneNumberKit.git", from: "4.1.0"),
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
    .package(url: "https://github.com/StanfordBDHG/zstd.git", exact: "1.5.8-beta.1")
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
    // MARK: HealthKitOnFHIR
    .library(name: "HealthKitOnFHIR", targets: ["HealthKitOnFHIR"]),
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
    .library(name: "SpeziFHIRHealthKit", targets: ["SpeziFHIRHealthKit"]),
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
    // MARK: XCTRuntimeAssertions
    .library(name: "RuntimeAssertions", targets: ["RuntimeAssertions"]),
    .library(name: "RuntimeAssertionsTesting", targets: ["RuntimeAssertionsTesting"]),
    .library(name: "XCTRuntimeAssertions", targets: ["XCTRuntimeAssertions"]),
    // MARK: XCTestExtensions
    .library(name: "XCTestApp", targets: ["XCTestApp"]),
    .library(name: "XCTestExtensions", targets: ["XCTestExtensions"]),
]

#if canImport(Darwin)
products += [
    // MARK: SpeziScheduler
    .library(name: "SpeziSchedulerUI", targets: ["SpeziSchedulerUI"]),
    // MARK: SpeziStudy
    .library(name: "SpeziStudy", targets: ["SpeziStudy"]),
]
#endif


var targets: [Target] = [
    // MARK: FHIRModelsExtensions
    .target(
        name: "FHIRModelsExtensions",
        dependencies: [
            .target(name: "FHIRPathParser"),
            .product(name: "ModelsR4", package: "FHIRModels")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "FHIRPathParser",
        dependencies: [
            .product(name: "Antlr4", package: "antlr4")
        ],
        exclude: [
            "ANTLUtils"
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "FHIRQuestionnaires",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels")
        ],
        resources: [
            .process("Resources")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "FHIRModelsExtensionsTests",
        dependencies: [
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRQuestionnaires")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "FHIRPathParserTests",
        dependencies: [
            .target(name: "FHIRPathParser")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: HealthKitOnFHIR
    .macro(
        name: "HealthKitOnFHIRMacrosImpl",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "HealthKitOnFHIRMacros",
        dependencies: [
            .target(name: "HealthKitOnFHIRMacrosImpl")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "HealthKitOnFHIR",
        dependencies: [
            .target(name: "HealthKitOnFHIRMacros"),
            .product(name: "ModelsR4", package: "FHIRModels"),
            .target(name: "FHIRModelsExtensions")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "Scripts"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "HealthKitOnFHIRTests",
        dependencies: [
            .target(name: "HealthKitOnFHIR"),
            .target(name: "SpeziFoundation")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "HealthKitOnFHIRMacrosTests",
        dependencies: [
            .target(name: "HealthKitOnFHIRMacros"),
            .target(name: "HealthKitOnFHIRMacrosImpl"),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: ResearchKitOnFHIR
    .target(
        name: "ResearchKitOnFHIR",
        dependencies: [
            .product(name: "ResearchKit", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .product(name: "ResearchKitSwiftUI", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .product(name: "ModelsR4", package: "FHIRModels"),
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRPathParser")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "ResearchKitOnFHIRTests",
        dependencies: [
            .target(name: "ResearchKitOnFHIR", condition: .when(traits: [researchKitTrait])),
            .target(name: "FHIRQuestionnaires")
        ],
        exclude: [
            "UITests"
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziTesting",
        dependencies: [
            .target(name: "Spezi")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpezi",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziTesting")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziTests",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziTesting"),
            .target(name: "RuntimeAssertionsTesting"),
            .product(name: "TestingExpectation", package: "swift-testing-expectation")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziAccessGuardTests",
        dependencies: [
            .target(name: "SpeziAccessGuard"),
            .target(name: "SpeziTesting"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: [
            "UITests"
        ],
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziAccount",
        dependencies: [
            .target(name: "SpeziAccount"),
            .target(name: "XCTestExtensions")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziAccountPhoneNumbers",
        dependencies: [
            .target(name: "SpeziAccount"),
            .product(name: "PhoneNumberKit", package: "PhoneNumberKit")
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziAccountTests",
        dependencies: [
            .target(name: "SpeziAccount"),
            .target(name: "SpeziAccountPhoneNumbers"),
            .target(name: "XCTRuntimeAssertions"),
            .target(name: "Spezi"),
            .target(name: "SpeziTesting"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: [
            "UITests"
        ],
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziAccountMacrosTests",
        dependencies: [
            .target(name: "SpeziAccountMacros"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "bin"
        ],
        resources: [
            .process("Resources")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziBluetoothServices",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "ByteCoding"),
            .target(name: "SpeziNumerics")
        ],
        plugins: [] + defaultPlugins
    ),
    .executableTarget(
        name: "TestPeripheral",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices"),
            .target(name: "ByteCoding")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziBluetoothTests",
        dependencies: [
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices")
        ],
        exclude: [
            "UITests"
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziChatTests",
        dependencies: [
            .target(name: "SpeziChat")
        ],
        exclude: [
            "UITests"
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziConsentTests",
        dependencies: [
            .target(name: "SpeziConsent"),
            .target(name: "SpeziFoundation"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: [
            "UITests"
        ],
        resources: [
            .process("Resources"),
            .process("__Snapshots__")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziContact
    .target(
        name: "SpeziContact",
        dependencies: [
            .target(name: "SpeziViews"),
            .target(name: "SpeziPersonalInfo")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziContactTests",
        dependencies: [
            .target(name: "SpeziContact")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
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
        resources: [
            .process("Resources")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziOmron",
        dependencies: [
            .target(name: "SpeziDevices"),
            .target(name: "SpeziBluetooth"),
            .target(name: "SpeziBluetoothServices")
        ],
        resources: [
            .process("Resources")
        ],
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
        exclude: [
            "UITests"
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziOmronTests",
        dependencies: [
            .target(name: "SpeziOmron"),
            .target(name: "SpeziBluetooth"),
            .target(name: "ByteCodingTesting")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziFHIR
    .target(
        name: "SpeziFHIR",
        dependencies: [
            .target(name: "Spezi"),
            .product(name: "ModelsR4", package: "FHIRModels"),
            .product(name: "ModelsDSTU2", package: "FHIRModels"),
            .target(name: "HealthKitOnFHIR"),
            .target(name: "SpeziHealthKit")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFHIRHealthKit",
        dependencies: [
            .target(name: "SpeziFHIR"),
            .target(name: "HealthKitOnFHIR"),
            .target(name: "SpeziHealthKit")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFHIRMockPatients",
        dependencies: [
            .target(name: "SpeziFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels")
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziFHIRTests",
        dependencies: [
            .target(name: "SpeziFHIR"),
            .target(name: "SpeziFHIRHealthKit"),
            .target(name: "HealthKitOnFHIR"),
            .target(name: "SpeziHealthKit")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziFileFormats
    .target(
        name: "SpeziFileFormats",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "EDFFormat",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "SpeziNumerics")
        ],
        swiftSettings: [
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
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziFirebase
    .target(
        name: "SpeziFirebase",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirebaseConfiguration",
        dependencies: [
            .target(name: "Spezi"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziFirebaseStorage",
        dependencies: [
            .target(name: "SpeziFirebaseConfiguration"),
            .target(name: "Spezi"),
            .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziFirebaseTests",
        dependencies: [
            .target(name: "SpeziFirebaseAccount"),
            .target(name: "SpeziFirebaseConfiguration"),
            .target(name: "SpeziFirestore")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "Dockerfile",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziFoundationTests",
        dependencies: [
            .target(name: "SpeziFoundation"),
            .target(name: "RuntimeAssertionsTesting")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziLocalizationTests",
        dependencies: [
            .target(name: "SpeziLocalization"),
            .target(name: "SpeziFoundation")
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "Sample Types/SampleTypeDefs.py",
            "Sample Types/SampleTypes.swift.gyb",
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml",
            "codecov.yml",
            "useGYB"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziHealthKitBulkExport",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalStorage", condition: .when(platforms: [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS]))
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziHealthKitUI",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziFoundation")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
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
        exclude: [
            "UITests"
        ],
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "FogNode",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMAnthropic",
        dependencies: [
            .target(name: "SpeziLLMOpenAI"),
            .target(name: "SpeziKeychainStorage")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLLMGemini",
        dependencies: [
            .target(name: "SpeziLLMOpenAI"),
            .target(name: "SpeziKeychainStorage")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "package.json",
            "package.json.license",
            "preprocess-openapi-spec.js",
            "package-lock.json",
            "README.md",
            "package-lock.json.license"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
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
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziLicense
    .target(
        name: "SpeziLicense",
        dependencies: [
            .product(name: "SwiftPackageList", package: "swift-package-list")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziLicenseTests",
        dependencies: [
            .target(name: "SpeziLicense"),
            .target(name: "Spezi")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziLocation
    .target(
        name: "SpeziLocation",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziLocationTests",
        dependencies: [
            .target(name: "SpeziLocation")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziNetworking
    .target(
        name: "SpeziNetworking",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "ByteCoding",
        dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziNumerics",
        dependencies: [
            .target(name: "ByteCoding"),
            .product(name: "NIOCore", package: "swift-nio")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "ByteCodingTesting",
        dependencies: [
            .target(name: "ByteCoding")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTByteCoding",
        dependencies: [
            .target(name: "ByteCoding")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "ByteCodingTests",
        dependencies: [
            .target(name: "ByteCoding"),
            .target(name: "ByteCodingTesting")
        ],
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
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziNotifications
    .target(
        name: "SpeziNotifications",
        dependencies: [
            .target(name: "Spezi")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziNotifications",
        dependencies: [
            .target(name: "SpeziNotifications")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziNotificationsUI",
        dependencies: [
            .target(name: "SpeziNotifications"),
            .target(name: "SpeziViews")
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziNotificationsTests",
        dependencies: [
            .target(name: "SpeziNotifications"),
            .target(name: "Spezi"),
            .target(name: "XCTSpezi")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziOnboarding
    .target(
        name: "SpeziOnboarding",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziViews")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziOnboardingTests",
        dependencies: [
            .target(name: "SpeziOnboarding")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziQuestionnaire
    .target(
        name: "SpeziQuestionnaire",
        dependencies: [
            .target(name: "SpeziQuestionnaireLegacy", condition: .when(traits: [researchKitTrait])),
            .target(name: "SpeziViews"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            .product(name: "Numerics", package: "swift-numerics")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziQuestionnaireCatalog",
        dependencies: [
            .target(name: "SpeziQuestionnaire")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziQuestionnaireFHIR",
        dependencies: [
            .target(name: "SpeziQuestionnaire"),
            .product(name: "ModelsR4", package: "FHIRModels"),
            .target(name: "FHIRModelsExtensions"),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .target(name: "SpeziFoundation")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziQuestionnaireLegacy",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels"),
            .product(name: "ResearchKit", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .product(name: "ResearchKitSwiftUI", package: "ResearchKit", condition: .when(platforms: [.iOS], traits: [researchKitTrait])),
            .target(name: "ResearchKitOnFHIR", condition: .when(platforms: [.iOS], traits: [researchKitTrait]))
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTSpeziQuestionnaire",
        dependencies: [
            .target(name: "XCTestExtensions")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziQuestionnaireTests",
        dependencies: [
            .target(name: "SpeziQuestionnaire"),
            .target(name: "SpeziQuestionnaireCatalog"),
            .target(name: "SpeziQuestionnaireFHIR"),
            .product(name: "ModelsR4", package: "FHIRModels"),
            .target(name: "FHIRModelsExtensions"),
            .target(name: "FHIRQuestionnaires")
        ],
        exclude: [
            "UITests"
        ],
        resources: [
            .process("Resources")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziSensorKitTests",
        dependencies: [
            .target(name: "SpeziSensorKit")
        ],
        exclude: [
            "UITests"
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziSpeech
    .target(
        name: "SpeziSpeech",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziSpeechRecognizer",
        dependencies: [
            .target(name: "Spezi")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziSpeechSynthesizer",
        dependencies: [
            .target(name: "Spezi")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziSpeechTests",
        dependencies: [
            .target(name: "SpeziSpeechRecognizer"),
            .target(name: "SpeziSpeechSynthesizer")
        ],
        exclude: [
            "UITests"
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziStorage
    .target(
        name: "SpeziStorage",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziKeychainStorage",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "RuntimeAssertions")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziLocalStorage",
        dependencies: [
            .target(name: "Spezi"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziKeychainStorage")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziStorageTests",
        dependencies: [
            .target(name: "SpeziLocalStorage"),
            .target(name: "XCTSpezi")
        ],
        exclude: [
            "UITests"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziStudy
    .target(
        name: "SpeziStudyDefinition",
        dependencies: [
            .product(name: "ModelsR4", package: "FHIRModels"),
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziHealthKitBulkExport"),
            .target(name: "SpeziFoundation"),
            .target(name: "SpeziLocalization"),
            .target(name: "SpeziScheduler"),
            .product(name: "DequeModule", package: "swift-collections"),
            .product(name: "Logging", package: "swift-log")
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziStudyTests",
        dependencies: { () -> [Target.Dependency] in
            var deps: [Target.Dependency] = [
                .target(name: "SpeziStudyDefinition"),
                .product(name: "ModelsR4", package: "FHIRModels")
            ]
            #if canImport(Darwin)
            deps += [
                .target(name: "SpeziStudy"),
                .target(name: "SpeziTesting")
            ]
            #endif
            return deps
        }(),
        exclude: [
            "UITests"
        ],
        resources: [
            .process("Resources/questionnaires"),
            .copy("Resources/assets")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        resources: [
            .process("Resources")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziPersonalInfo",
        dependencies: [
            .target(name: "SpeziViews")
        ],
        resources: [
            .process("Resources")
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "SpeziValidation",
        dependencies: [
            .target(name: "SpeziViews"),
            .target(name: "SpeziFoundation"),
            .product(name: "OrderedCollections", package: "swift-collections")
        ],
        resources: [
            .process("Resources")
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "SpeziViewsTests",
        dependencies: [
            .target(name: "SpeziViews"),
            .target(name: "SpeziValidation"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        exclude: [
            "UITests"
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: XCTHealthKit
    .target(
        name: "XCTHealthKit",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "XCTHealthKitTests",
        dependencies: [
            .target(name: "XCTHealthKit")
        ],
        exclude: [
            "UITests"
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: XCTRuntimeAssertions
    .target(
        name: "RuntimeAssertions",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "RuntimeAssertionsTesting",
        dependencies: [
            .target(name: "RuntimeAssertions")
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTRuntimeAssertions",
        dependencies: [
            .target(name: "RuntimeAssertions")
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "RuntimeAssertionsTests",
        dependencies: [
            .target(name: "RuntimeAssertions"),
            .target(name: "RuntimeAssertionsTesting")
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "XCTRuntimeAssertionsTests",
        dependencies: [
            .target(name: "XCTRuntimeAssertions")
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: XCTestExtensions
    .target(
        name: "XCTestApp",
        plugins: [] + defaultPlugins
    ),
    .target(
        name: "XCTestExtensions",
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md"
        ],
        plugins: [] + defaultPlugins
    ),
    .testTarget(
        name: "XCTestExtensionsTests",
        dependencies: [
            .target(name: "XCTestExtensions")
        ],
        exclude: [
            "UITests"
        ],
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
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziScheduler
    .target(
        name: "SpeziSchedulerUI",
        dependencies: [
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziViews")
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
            .target(name: "XCTRuntimeAssertions"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        exclude: [
            "UITests"
        ],
        resources: [
            .process("Resources")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziScheduler
    .testTarget(
        name: "SpeziSchedulerUITests",
        dependencies: [
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziSchedulerUI"),
            .target(name: "XCTSpezi"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing", condition: .when(platforms: [.iOS]))
        ],
        resources: [
            .process("__Snapshots__")
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziStudy
    .target(
        name: "SpeziStudy",
        dependencies: [
            .target(name: "SpeziStudyDefinition"),
            .target(name: "Spezi"),
            .product(name: "ModelsR4", package: "FHIRModels"),
            .target(name: "SpeziHealthKit"),
            .target(name: "SpeziLocalStorage"),
            .target(name: "SpeziScheduler"),
            .target(name: "SpeziSchedulerUI"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        exclude: [
            "CONTRIBUTORS.md",
            "LICENSE.md",
            "LICENSES",
            "README.md",
            "REUSE.toml"
        ],
        swiftSettings: [
            .enableUpcomingFeature("ExistentialAny")
        ],
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
        plugins: [] + defaultPlugins
    ),
    // MARK: SpeziHealthKit
    .executableTarget(
        name: "Codegen",
        dependencies: [
            .target(name: "SpeziHealthKit"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ],
        exclude: [
            "HKTypeIdentifierDefs+Linux.swift.gyb"
        ],
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
    targets: targets
)
