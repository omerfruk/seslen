// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Seslen",
    platforms: [.macOS(.v14)],
    targets: [
        // Uyarı sesleri macOS'un yerleşik sistem seslerinden geldiği için
        // pakete gömülü ses kaynağı yok.
        .executableTarget(
            name: "Seslen",
            path: "Sources/Seslen",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
