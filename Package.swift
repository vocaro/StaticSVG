// swift-tools-version: 6.2
import PackageDescription

// The renderer is a prebuilt static library, so consumers need no Rust. A release takes it from
// its GitHub release asset, pinned by checksum; `STATICSVG_LOCAL_RESVG=1` takes the one
// `scripts/build-resvg.sh` writes to `Resvg/Resvg.xcframework` instead (doc/maintenance.md).
let resvg: Target = Context.environment["STATICSVG_LOCAL_RESVG"] == "1"
    ? .binaryTarget(name: "CResvg", path: "Resvg/Resvg.xcframework")
    : .binaryTarget(name: "CResvg",
                    url: "https://github.com/vocaro/StaticSVG/releases/download/0.1.1/Resvg.xcframework.zip",
                    checksum: "05106de42f7b84c85116ef34d2daf7779ae0c41106ae95e8d161738e964a0ae0")

let package = Package(
    name: "StaticSVG",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "StaticSVG", targets: ["StaticSVG"]),
    ],
    targets: [
        resvg,
        .target(name: "StaticSVG", dependencies: ["CResvg"]),
        .testTarget(name: "StaticSVGTests", dependencies: ["StaticSVG", "CResvg"]),
    ]
)
