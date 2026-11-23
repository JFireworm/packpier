// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeChatCeladon",
    platforms: [.macOS(.v12)],
    products: [.library(name: "WeChatCeladon", targets: ["WeChatCeladon"])],
    targets: [
        .target(name: "WeChatCeladon"),
        .testTarget(name: "WeChatCeladonTests", dependencies: ["WeChatCeladon"])
    ]
)
