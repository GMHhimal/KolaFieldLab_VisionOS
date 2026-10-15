//
//  MaterialPalette.swift
//  KolaFieldLab
//
//  Caches materials by quantised colour so hundreds of leaves share a handful of
//  material instances (fewer GPU state changes, less memory churn per frame).
//

import RealityKit
import UIKit

@MainActor
final class MaterialPalette {
    static let shared = MaterialPalette()

    private var cache: [Int: SimpleMaterial] = [:]

    /// Colours are quantised to 32 levels per channel before lookup.
    func material(_ color: RGB, roughness: Float = 0.75) -> SimpleMaterial {
        let key = Self.key(color, roughness: roughness)
        if let cached = cache[key] { return cached }
        let material = SimpleMaterial(color: UIColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1),
                                      roughness: .float(roughness),
                                      isMetallic: false)
        cache[key] = material
        return material
    }

    var count: Int { cache.count }

    private static func key(_ color: RGB, roughness: Float) -> Int {
        func q(_ v: Float) -> Int { Int((max(0, min(1, v)) * 31).rounded()) }
        return (q(color.r) << 15) | (q(color.g) << 10) | (q(color.b) << 5) | q(roughness)
    }

    // Shared, fixed colours.
    static let stem = RGB(0.24, 0.42, 0.16)
    static let soil = RGB(0.30, 0.20, 0.12)
    static let pot = RGB(0.62, 0.32, 0.18)
    static let fruit = RGB(0.85, 0.16, 0.10)
    static let deadLeaf = RGB(0.34, 0.24, 0.12)
    static let spray = RGB(0.55, 0.85, 1.0)
}
