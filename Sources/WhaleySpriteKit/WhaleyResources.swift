import Foundation

#if canImport(UIKit) && canImport(SpriteKit) && canImport(WhaleyObjectiveC)
import UIKit
import SpriteKit
import WhaleyObjectiveC

public enum WhaleyResources {
    public static var bundled: Bundle { .module }

    @MainActor public static func configure(bundle: Bundle? = nil) {
        WhaleySrcSetResourceBundle(bundle ?? .module)
    }

    public static func url(_ name: String, in bundle: Bundle? = nil) -> URL? {
        if WhaleySrcUsesWhalelandArt(),
           ["flame01.png", "flame02.png", "spout.png",
            "tileset.png", "tileset2.png", "tileset3.png"].contains(name),
           let alternate = url("whaleland-" + name, in: bundle) {
            return alternate
        }
        let bundle = bundle ?? .module
        let path = name as NSString
        let ext = path.pathExtension.isEmpty ? nil : path.pathExtension
        return bundle.url(forResource: path.deletingPathExtension, withExtension: ext)
            ?? bundle.url(forResource: path.deletingPathExtension, withExtension: ext, subdirectory: "Resources")
    }

    public static func texture(_ name: String, in bundle: Bundle? = nil) -> SKTexture {
        let texture: SKTexture
        if let url = url(name, in: bundle), let image = UIImage(contentsOfFile: url.path) {
            texture = SKTexture(image: image)
        } else {
            texture = SKTexture(imageNamed: name)
        }
        let filename = (name as NSString).lastPathComponent
        let stylePrefix = "whaleland-"
        let originalName = filename.hasPrefix(stylePrefix) ? String(filename.dropFirst(stylePrefix.count)) : filename
        switch originalName {
        case "player.png", "player-win.png", "spout.png", "flame01.png", "flame02.png",
             "coin.png", "goal01.png", "tileset.png", "tileset2.png", "tileset3.png",
             "whaley-expressions.png", "whaley-win-expressions.png":
            texture.filteringMode = .nearest
        default:
            break
        }
        return texture
    }
}
#endif
