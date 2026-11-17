// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DeskPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeskPet", targets: ["DeskPet"])
    ],
    targets: [
        .target(name: "DeskPetCore", path: "Sources/DeskPetCore"),
        .executableTarget(
            name: "DeskPet",
            dependencies: ["DeskPetCore"],
            path: "Sources/DeskPet",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "DeskPetSelfTest",
            dependencies: ["DeskPetCore"],
            path: "Sources/DeskPetSelfTest"
        ),
    ]
)
