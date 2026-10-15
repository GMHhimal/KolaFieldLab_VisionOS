//
//  SymptomModel.swift
//  KolaFieldLab
//
//  Pure functions that turn a disease's progress (0…1) into what each leaf
//  should look like. Kept free of RealityKit so they can be unit tested.
//

import Foundation

struct LeafAppearance: Equatable {
    var color: RGB
    /// Number of lesions/patches to show on this leaf.
    var visibleLesions: Int
    /// Radians the leaf cups upward (leaf-curl viruses).
    var curl: Float
    /// Leaf size multiplier (viruses stunt new growth).
    var scale: Float
}

enum SymptomModel {
    /// Symptoms start on old, low leaves and climb the plant: a leaf's local
    /// progress lags the plant's overall progress according to its age.
    static func localProgress(plantProgress: Double, leafAge: Float) -> Double {
        let lag = Double(leafAge) * 0.55
        return min(1, max(0, (plantProgress - lag) / (1 - lag * 0.6)))
    }

    static func lesionCapacity(for visual: VisualProfile) -> Int {
        visual.pattern == .mosaic ? 6 : visual.maxLesions
    }

    static func appearance(for visual: VisualProfile, plantProgress: Double, leafAge: Float, leafIndex: Int) -> LeafAppearance {
        let local = Float(localProgress(plantProgress: plantProgress, leafAge: leafAge))
        let capacity = lesionCapacity(for: visual)
        switch visual.pattern {
        case .spots:
            return LeafAppearance(color: RGB.mix(.leafGreen, visual.chlorosisColor, max(0, local - 0.35) * 1.2),
                                  visibleLesions: Int((Float(capacity) * min(1, local * 1.3)).rounded()),
                                  curl: 0, scale: 1)
        case .blotches:
            return LeafAppearance(color: RGB.mix(.leafGreen, visual.lesionColor, max(0, local - 0.25) * 1.1),
                                  visibleLesions: Int((Float(capacity) * min(1, local * 1.6)).rounded()),
                                  curl: local * 0.3, scale: 1 - local * 0.1)
        case .mosaic:
            let mottled = leafIndex % 2 == 0 ? local * 0.7 : local * 0.25
            return LeafAppearance(color: RGB.mix(.leafGreen, visual.chlorosisColor, mottled),
                                  visibleLesions: Int((Float(capacity) * local).rounded()),
                                  curl: local * 0.15, scale: 1 - local * 0.15)
        case .curl:
            return LeafAppearance(color: RGB.mix(.leafGreen, visual.chlorosisColor, local * 0.8),
                                  visibleLesions: 0,
                                  curl: local * 1.1, scale: 1 - local * 0.45)
        }
    }

    /// Colour of a field plant at a given severity (0 healthy … 1 dead).
    static func fieldColor(for visual: VisualProfile, severity: Double, treated: Bool) -> RGB {
        let s = Float(min(1, max(0, severity)))
        let diseased = s < 0.5
            ? RGB.mix(.leafGreen, visual.chlorosisColor, s * 2)
            : RGB.mix(visual.chlorosisColor, MaterialPaletteColors.deadLeaf, (s - 0.5) * 2)
        return treated ? RGB.mix(diseased, .leafGreen, 0.35) : diseased
    }
}

/// Colour constants usable outside the main actor (MaterialPalette is @MainActor).
enum MaterialPaletteColors {
    static let deadLeaf = RGB(0.34, 0.24, 0.12)
}
