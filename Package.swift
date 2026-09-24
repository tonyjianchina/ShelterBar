// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShelterBar",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShelterBarCore", targets: ["ShelterBarCore"]),
        .executable(name: "ShelterBar", targets: ["ShelterBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "ShelterBarCore"),
        .executableTarget(
            name: "ShelterBar",
            dependencies: ["ShelterBarCore"]
        ),
        .testTarget(
            name: "ShelterBarCoreTests",
            dependencies: [
                "ShelterBarCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ShelterBarTests",
            dependencies: [
                "ShelterBar",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
