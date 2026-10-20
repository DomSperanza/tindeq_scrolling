// swift-tools-version:5.9
import PackageDescription

// Platform-independent logic shared by the iOS app: Progressor protocol parsing,
// the force gate state machine, and weight unit helpers. Foundation-only so it
// can be built and tested on Linux (`swift test`) as well as in Xcode.
let package = Package(
    name: "TindeqCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TindeqCore", targets: ["TindeqCore"]),
    ],
    targets: [
        .target(name: "TindeqCore"),
        .testTarget(name: "TindeqCoreTests", dependencies: ["TindeqCore"]),
    ]
)
