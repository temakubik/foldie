// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Foldie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Foldie", targets: ["Foldie"])
    ],
    targets: [
        .executableTarget(
            name: "Foldie",
            path: "Sources/Foldie",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
