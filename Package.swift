// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacMount",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacMount",
            targets: ["MacMount"]
        ),
    ],
    dependencies: [
        // Dependencies can be added here if needed
    ],
    targets: [
        .executableTarget(
            name: "MacMount",
            dependencies: [],
            path: ".",
            exclude: [
                "Tests",
                "README.md",
                ".gitignore",
                "Package.swift",
                "Makefile",
                "Info.plist",
                "MacMount.entitlements",
                "BuildConfig.xcconfig",
                "MacMount.app",
                "Distribution",
                "Documentation",
                "Resources",
                "Scripts",
                "setup-env.sh",
                "build-app.sh",
                "create-dmg.sh",
                "notarize.sh",
                "SIGNING_QUICKSTART.md",
                "CLAUDE.md",
                "quick-test.sh",
                "test-preferences.sh",
                ".env.example"
            ],
            sources: [
                "App",
                "Core",
                "UI",
                "Extensions"
            ]
        ),
        .testTarget(
            name: "MacMountTests",
            dependencies: ["MacMount"],
            path: "Tests"
        ),
    ]
)