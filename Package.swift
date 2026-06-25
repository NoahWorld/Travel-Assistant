// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TravelExpenseDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TravelExpenseDesk", targets: ["TravelExpenseDesk"])
    ],
    targets: [
        .executableTarget(name: "TravelExpenseDesk")
    ]
)
