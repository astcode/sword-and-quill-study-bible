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
        .target(
            name: "KJVStudyBible",
            dependencies: [
                "CMagQLite",
            ],
            resources: [
                .copy("Resources/kjv_reference.mql"),
                .copy("Resources/kjv_reference.mql.pages"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
