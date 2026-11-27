// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KJVStudyBible",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "KJVStudyBible",
            targets: ["KJVStudyBible"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "CMagQLite",
            path: "Vendor/MagQLite.xcframework"
        ),
        .binaryTarget(
            name: "SherpaOnnxC",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v2.0.3-ios-static.xcframework.zip",
            checksum: "36603efc0908a18a3b4b5ec1a81a15accddbe9948720bf4d931ee14506f42481"
        ),
        .binaryTarget(
            name: "OnnxRuntimeIOS",
            url: "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip",
            checksum: "2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599"
        ),
        .target(
            name: "KJVStudyBible",
            dependencies: [
                "CMagQLite",
                "SherpaOnnxC",
                "OnnxRuntimeIOS",
            ],
            resources: [
                .copy("Resources/kjv_reference.mql"),
                .copy("Resources/kjv_reference.mql.pages"),
                .copy("Resources/StarterModules"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("c++"),
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
