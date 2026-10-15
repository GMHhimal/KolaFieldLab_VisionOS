//
//  FieldScene.swift
//  KolaFieldLab
//
//  The immersive tomato field: a 7 × 7 grid of procedural plants laid out on the
//  real floor in front of the user, procedural rain, and per-plant visuals that
//  mirror the outbreak simulation. Meshes and materials are shared across all
//  plants to keep draw cost low (~300 entities).
//

import RealityKit
import simd
import UIKit

@MainActor
final class FieldScene {
    struct PlantVisual {
        let root: Entity
        let leaves: [ModelEntity]
        let sprayRing: ModelEntity
    }

    let root = Entity()
    private(set) var plants: [PlantVisual] = []
    private let rainRoot = Entity()
    private let palette = MaterialPalette.shared

    /// Distance between plants (metres) and where the field starts in front of the user.
    let spacing: Float = 0.45
    let frontZ: Float = -1.1

    private static let leafMesh = MeshResource.generateSphere(radius: 1)
    private static let stemMesh = MeshResource.generateBox(width: 0.02, height: 0.36, depth: 0.02, cornerRadius: 0.006)
    private static let ringMesh = MeshResource.generateBox(width: 0.24, height: 0.004, depth: 0.24, cornerRadius: 0.12)
    private static let dropMesh = MeshResource.generateBox(width: 0.004, height: 0.07, depth: 0.004)

    private var lastSignature: [Int] = []

    func build(size: Int) {
        guard plants.isEmpty else { return }
        root.name = "Field"
        let extent = Float(size - 1) * spacing
        let centerZ = frontZ - extent / 2

        // Soil bed
        let bed = ModelEntity(mesh: .generatePlane(width: extent + 0.6, depth: extent + 0.6, cornerRadius: 0.1),
                              materials: [palette.material(MaterialPalette.soil, roughness: 1)])
        bed.position = [0, 0.002, centerZ]
        root.addChild(bed)

        var rng = SplitMix64(seed: 11)
        for index in 0..<(size * size) {
            let row = index / size, column = index % size
            let plantRoot = Entity()
            plantRoot.name = "Plant-\(index)"
            plantRoot.position = [Float(column) * spacing - extent / 2, 0, frontZ - Float(row) * spacing]

            let stem = ModelEntity(mesh: Self.stemMesh, materials: [palette.material(MaterialPalette.stem)])
            stem.position = [0, 0.18, 0]
            plantRoot.addChild(stem)

            var leaves: [ModelEntity] = []
            for leafIndex in 0..<6 {
                let leaf = ModelEntity(mesh: Self.leafMesh, materials: [palette.material(.leafGreen)])
                let height = 0.1 + Float(leafIndex) * 0.045
                let yaw = Float(leafIndex) * 2.2 + Float.random(in: 0..<0.6, using: &rng)
                leaf.position = [cos(yaw) * 0.06, height, sin(yaw) * 0.06]
                leaf.orientation = simd_quatf(angle: -yaw, axis: [0, 1, 0]) * simd_quatf(angle: 0.3, axis: [0, 0, 1])
                leaf.scale = [0.07 - Float(leafIndex) * 0.006, 0.006, 0.035 - Float(leafIndex) * 0.003]
                plantRoot.addChild(leaf)
                leaves.append(leaf)
            }

            let ring = ModelEntity(mesh: Self.ringMesh, materials: [palette.material(MaterialPalette.spray, roughness: 0.2)])
            ring.position = [0, 0.006, 0]
            ring.isEnabled = false
            plantRoot.addChild(ring)

            // Tap target covering the whole plant.
            plantRoot.components.set(InputTargetComponent())
            plantRoot.components.set(CollisionComponent(shapes: [.generateBox(width: 0.3, height: 0.42, depth: 0.3).offsetBy(translation: [0, 0.21, 0])]))
            plantRoot.components.set(HoverEffectComponent())
            plantRoot.components.set(FieldPlantComponent(index: index))
            plantRoot.components.set(SwayComponent(phase: Float.random(in: 0..<6.28, using: &rng), amplitude: 0.05,
                                                   speed: Float.random(in: 1.1...1.7, using: &rng)))
            root.addChild(plantRoot)
            plants.append(PlantVisual(root: plantRoot, leaves: leaves, sprayRing: ring))
        }

        buildRain(extent: extent, centerZ: centerZ, rng: &rng)
    }

    private func buildRain(extent: Float, centerZ: Float, rng: inout SplitMix64) {
        rainRoot.name = "Rain"
        let material = UnlitMaterial(color: .init(red: 0.75, green: 0.85, blue: 1, alpha: 0.7))
        for _ in 0..<160 {
            let drop = ModelEntity(mesh: Self.dropMesh, materials: [material])
            let top = Float.random(in: 2.2...2.8, using: &rng)
            drop.position = [Float.random(in: -extent / 2 - 0.3...extent / 2 + 0.3, using: &rng),
                             Float.random(in: 0...top, using: &rng),
                             centerZ + Float.random(in: -extent / 2 - 0.3...extent / 2 + 0.3, using: &rng)]
            drop.components.set(RainDropComponent(speed: Float.random(in: 3.5...5, using: &rng), top: top))
            rainRoot.addChild(drop)
        }
        rainRoot.isEnabled = false
        root.addChild(rainRoot)
    }

    // MARK: Sync with simulation

    func apply(cells: [PlantState], disease: LabDisease?, raining: Bool) {
        rainRoot.isEnabled = raining
        guard let disease, cells.count == plants.count else { return }

        // Skip work when nothing visible changed (the update closure can run often).
        let signature = cells.map(Self.signature) + [disease.id.hashValue]
        guard signature != lastSignature else { return }
        lastSignature = signature

        for (index, state) in cells.enumerated() {
            let plant = plants[index]
            var treated = false
            if case .treated = state { treated = true }
            let color = SymptomModel.fieldColor(for: disease.visual, severity: state.visualSeverity, treated: treated)
            let material = palette.material(color)
            for leaf in plant.leaves { leaf.model?.materials = [material] }
            plant.sprayRing.isEnabled = treated

            // Lost plants slump over and stop swaying.
            if var sway = plant.root.components[SwayComponent.self] {
                let lost = state == .lost
                sway.amplitude = lost ? 0 : 0.05
                sway.baseRotation = lost
                    ? simd_quatf(angle: 1.1, axis: simd_normalize(SIMD3<Float>(1, 0, Float(index % 3) - 1)))
                    : simd_quatf(angle: 0, axis: [0, 1, 0])
                plant.root.components.set(sway)
            }
        }
    }

    private static func signature(_ state: PlantState) -> Int {
        switch state {
        case .healthy: 0
        case .incubating: 1
        case .infected(let severity): 100 + Int(severity * 20)
        case .treated(let severity): 200 + Int(severity * 20)
        case .lost: 300
        }
    }

    func plantIndex(for entity: Entity) -> Int? {
        var current: Entity? = entity
        while let candidate = current {
            if let component = candidate.components[FieldPlantComponent.self] { return component.index }
            current = candidate.parent
        }
        return nil
    }

    /// Quick scale "pop" to acknowledge a tap.
    func pulse(_ index: Int, success: Bool) {
        guard plants.indices.contains(index) else { return }
        let entity = plants[index].root
        var up = entity.transform
        up.scale = SIMD3(repeating: success ? 1.25 : 0.85)
        entity.move(to: up, relativeTo: entity.parent, duration: 0.15, timingFunction: .easeOut)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            var back = entity.transform
            back.scale = .one
            entity.move(to: back, relativeTo: entity.parent, duration: 0.25, timingFunction: .easeInOut)
        }
    }
}
