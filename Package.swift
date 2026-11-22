// swift-tools-version:5.9
import PackageDescription

// The GitHub organization of the suite's repositories: the one name to change should it be renamed (the
// suite repository's scripts/rename-organization.sh does it in every repository).
let organization = "love-suite"

// Explorer: the file manager of the suite, with its own desktop and Explorer windows. Finder's desktop,
// which it hides, is put back by Suite Guard should it vanish. The Dock is an app of its own (suite-bar). Its settings are a library of their own, which Suite Settings reads for Explorer's tabs.
let suiteCore = Target.Dependency.product(name: "SuiteCore", package: "suite-core")
let finderGuard = Target.Dependency.product(name: "FinderGuard", package: "suite-guard")
let filesCore = Target.Dependency.product(name: "SuiteFilesCore", package: "suite-files")
let filesUI = Target.Dependency.product(name: "SuiteFilesUI", package: "suite-files")

let package = Package(
    name: "Explorer",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ExplorerSettings", targets: ["ExplorerSettings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/\(organization)/suite-core", .upToNextMinor(from: "27.1.0-dev.1")),
        .package(url: "https://github.com/\(organization)/suite-guard", .upToNextMinor(from: "27.1.0-dev.1")),
        .package(url: "https://github.com/\(organization)/suite-files", .upToNextMinor(from: "27.1.0-dev.1")),
    ],
    targets: [
        // Explorer's settings as Explorer and Suite Settings read and write them. No UI.
        .target(name: "ExplorerSettings", dependencies: [suiteCore, filesCore]),
        .testTarget(name: "ExplorerSettingsTests", dependencies: ["ExplorerSettings", suiteCore, filesCore]),

        // File logic (no UI, unit-tested), then its AppKit layer, then the app.
        .target(
            name: "ExplorerCore",
            dependencies: [suiteCore, filesCore, "ExplorerSettings"],
            linkerSettings: [.linkedFramework("CoreServices")]
        ),
        .target(
            name: "ExplorerUI",
            dependencies: ["ExplorerCore", "ExplorerSettings", suiteCore, filesCore, filesUI],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Quartz"), .linkedFramework("ServiceManagement"),
                             .linkedFramework("NetFS")]
        ),
        // The app: desktop, Explorer windows, default folder viewer and Finder redirect.
        .executableTarget(
            name: "Explorer",
            dependencies: ["ExplorerCore", "ExplorerUI", "ExplorerSettings", suiteCore, filesCore, filesUI, finderGuard],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ExplorerCoreTests",
                    dependencies: ["ExplorerCore", "ExplorerSettings", suiteCore, filesCore]),

        // Suite Trash: a root daemon installed by SMAppService that erases, for Explorer alone, Trash items
        // needing root. What it accepts (callers, paths) is decided in its UI-free library.
        .target(name: "TrashCore"),
        .testTarget(name: "TrashCoreTests", dependencies: ["TrashCore", suiteCore, filesCore]),
        .executableTarget(name: "Trash", dependencies: ["TrashCore"]),
    ]
)
