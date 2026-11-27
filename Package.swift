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
        .target(
            name: "KJVStudyBible",
            resources: [
                .copy("Resources/kjv_reference.sqlite"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
