// swift-tools-version: 6.0
import PackageDescription

// Build the original cocos2d, CocosDenshion and kazmath sources as one
// Clang target. The 2010 engine assumes shared, non-modular header visibility.
// Keep vendored sources unchanged; expose one SwiftPM library product.
let package = Package(
    name: "WhaleyCocos2D",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "WhaleyCocos2D", targets: ["WhaleyCocos2D"])
    ],
    targets: [
        .target(
            name: "WhaleyCocos2D",
            path: "Sources/Cocos2D",
            exclude: [
                "cocos2d/Platforms/Mac",
                "cocos2d/CCPhysicsSprite.mm",
                "cocos2d/CCPhysicsDebugNode.m",
                "CocosDenshion/CDXMacOSXSupport.m",
                "CocosDenshion/CDXMacOSXSupport.h",
                "kazmath/src/neon_matrix_impl.c"
            ],
            sources: ["cocos2d", "CocosDenshion", "kazmath/src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("cocos2d"),
                .headerSearchPath("cocos2d/Support"),
                .headerSearchPath("cocos2d/Platforms"),
                .headerSearchPath("cocos2d/Platforms/iOS"),
                .headerSearchPath("CocosDenshion"),
                .headerSearchPath("kazmath/include"),
                .unsafeFlags(["-fno-objc-arc", "-fcommon"])
            ],
            linkerSettings: [
                .linkedFramework("OpenGLES"),
                .linkedFramework("OpenAL"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UIKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedLibrary("z"),
                .linkedLibrary("xml2")
            ]
        )
    ]
)
