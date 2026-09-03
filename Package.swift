// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "SimpleLocalizeOTA",
  platforms: [
    .iOS(.v13),
    .macOS(.v11),
    .tvOS(.v13),
    .watchOS(.v6)
  ],
  products: [
    .library(name: "SimpleLocalizeOTA", targets: ["SimpleLocalizeOTA"])
  ],
  targets: [
    .target(name: "SimpleLocalizeOTA"),
    .testTarget(name: "SimpleLocalizeOTATests", dependencies: ["SimpleLocalizeOTA"])
  ]
)
