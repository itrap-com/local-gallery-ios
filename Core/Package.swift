// swift-tools-version:5.9
// Platform-free logic shared by the app and tested on Linux (no Apple-only frameworks here).
import PackageDescription

let package = Package(
    name: "GalleryCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GalleryCore", targets: ["GalleryCore"]),
    ],
    targets: [
        .target(name: "GalleryCore"),
        .testTarget(name: "GalleryCoreTests", dependencies: ["GalleryCore"]),
    ]
)
