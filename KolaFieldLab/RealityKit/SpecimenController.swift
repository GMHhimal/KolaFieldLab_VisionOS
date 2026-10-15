//
//  SpecimenController.swift
//  KolaFieldLab
//
//  Builds a procedural, life-like tomato plant from RealityKit primitives and
//  updates its symptoms as the disease stage changes. No 3D assets are needed,
//  so every disease can be shown at any stage on demand.
//

import RealityKit
import simd

@MainActor
final class SpecimenController {
    struct LeafVisual {
        let container: Entity
        let blade: ModelEntity
        let lesions: [ModelEntity]
        let halos: [ModelEntity]
        let age: Float
        let index: Int
        let baseRotation: simd_quatf
    }

    let root = Entity()
    private let turntable = Entity()
    private(set) var leaves: [LeafVisual] = []
    private var fruits: [ModelEntity] = []
    private var builtFor: String?
    private var callout: Entity?

    private let palette = MaterialPalette.shared
    private static let leafMesh = MeshResource.generateSphere(radius: 1)
    private static let lesionMesh = MeshResource.generateSphere(radius: 1)

    init() {
        root.name = "SpecimenRoot"
        turntable.name = "Turntable"
        root.addChild(turntable)
    }

    // MARK: Build

    /// Rebuilds the plant for a disease (lesion layout depends on the disease's pattern).
    func build(for disease: LabDisease) {
        guard builtFor != disease.id else { return }
        builtFor = disease.id
        turntable.children.removeAll()
        leaves.removeAll()
        fruits.removeAll()

        var rng = SplitMix64(seed: 7)

        // Pot and soil
        let pot = ModelEntity(mesh: .generateBox(width: 0.17, height: 0.13, depth: 0.17, cornerRadius: 0.02),
                              materials: [palette.material(MaterialPalette.pot)])
        pot.position = [0, 0.065, 0]
        let soil = ModelEntity(mesh: .generateBox(width: 0.15, height: 0.01, depth: 0.15, cornerRadius: 0.004),
                               materials: [palette.material(MaterialPalette.soil, roughness: 1)])
        soil.position = [0, 0.13, 0]
        makeInteractive(pot, shape: .generateBox(width: 0.17, height: 0.13, depth: 0.17))
        turntable.addChild(pot)
        turntable.addChild(soil)

        // Main stem
        let stemHeight: Float = 0.46
        let stem = ModelEntity(mesh: .generateBox(width: 0.016, height: stemHeight, depth: 0.016, cornerRadius: 0.006),
                               materials: [palette.material(MaterialPalette.stem)])
        stem.position = [0, 0.13 + stemHeight / 2, 0]
        makeInteractive(stem, shape: .generateBox(width: 0.03, height: stemHeight, depth: 0.03))
        turntable.addChild(stem)

        // Branches: 5 levels spiralling up the stem, 3 leaves each.
        let levels = 5
        for level in 0..<levels {
            let height: Float = 0.2 + Float(level) * 0.075
            let yaw = Float(level) * 2.4                      // golden-angle-ish phyllotaxis
            let age = Float(level) / Float(levels - 1)
            let branchPivot = Entity()
            branchPivot.position = [0, height, 0]
            branchPivot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            turntable.addChild(branchPivot)

            let branchLength: Float = 0.17 - Float(level) * 0.015
            let branch = ModelEntity(mesh: .generateBox(width: branchLength, height: 0.008, depth: 0.008, cornerRadius: 0.003),
                                     materials: [palette.material(MaterialPalette.stem)])
            branch.position = [branchLength / 2, 0, 0]
            branch.orientation = simd_quatf(angle: 0.35, axis: [0, 0, 1])
            branchPivot.addChild(branch)

            for position in 0..<3 {
                let along = branchLength * (0.45 + Float(position) * 0.27)
                let leafIndex = leaves.count
                let container = Entity()
                container.position = [along * cos(0.35), along * sin(0.35), position == 1 ? 0.025 : -0.025]
                let base = simd_quatf(angle: position == 1 ? 0.5 : -0.5, axis: [0, 1, 0])
                container.orientation = base
                branchPivot.addChild(container)

                let size: Float = 1 - age * 0.35
                let blade = ModelEntity(mesh: Self.leafMesh, materials: [palette.material(.leafGreen)])
                blade.scale = [0.045 * size, 0.004, 0.022 * size]
                makeInteractive(blade, shape: .generateSphere(radius: 1))
                blade.components.set(LeafComponent(branch: level, position: position, age: age))
                blade.components.set(HoverEffectComponent())
                container.addChild(blade)

                // Pre-create lesions at random spots on the blade; they are toggled by stage.
                var lesions: [ModelEntity] = []
                var halos: [ModelEntity] = []
                let capacity = SymptomModel.lesionCapacity(for: disease.visual)
                let lesionColor = disease.visual.pattern == .mosaic ? disease.visual.chlorosisColor : disease.visual.lesionColor
                for _ in 0..<capacity {
                    let angle = Float.random(in: 0..<(2 * .pi), using: &rng)
                    let radius = sqrt(Float.random(in: 0..<1, using: &rng)) * 0.75
                    let x = cos(angle) * radius * 0.045 * size
                    let z = sin(angle) * radius * 0.022 * size
                    let lesionSize = disease.visual.pattern == .mosaic ? 0.012 * size : disease.visual.lesionSize * Float.random(in: 0.7...1.2, using: &rng)

                    if let halo = disease.visual.haloColor {
                        let haloEntity = ModelEntity(mesh: Self.lesionMesh, materials: [palette.material(halo)])
                        haloEntity.scale = [lesionSize * 1.5, 0.0012, lesionSize * 1.5]
                        haloEntity.position = [x, 0.0038, z]
                        haloEntity.isEnabled = false
                        container.addChild(haloEntity)
                        halos.append(haloEntity)
                    }
                    let lesion = ModelEntity(mesh: Self.lesionMesh, materials: [palette.material(lesionColor, roughness: 0.9)])
                    lesion.scale = [lesionSize, 0.0015, lesionSize]
                    lesion.position = [x, 0.0045, z]
                    lesion.isEnabled = false
                    container.addChild(lesion)
                    lesions.append(lesion)
                }

                leaves.append(LeafVisual(container: container, blade: blade, lesions: lesions, halos: halos,
                                         age: age, index: leafIndex, baseRotation: base))
            }

            // Fruit trusses on the lower branches.
            if level < 2 {
                for fruitIndex in 0..<2 {
                    let fruit = ModelEntity(mesh: .generateSphere(radius: 0.022), materials: [palette.material(MaterialPalette.fruit, roughness: 0.35)])
                    fruit.position = [branchLength * 0.55, -0.035 - Float(fruitIndex) * 0.04, Float(fruitIndex) * 0.02]
                    branchPivot.addChild(fruit)
                    fruits.append(fruit)
                }
            }
        }

        turntable.components.set(SwayComponent(phase: 0, amplitude: 0.025, speed: 0.9))
        if let callout { root.addChild(callout) }
    }

    private func makeInteractive(_ entity: ModelEntity, shape: ShapeResource) {
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [shape]))
    }

    // MARK: Update

    func apply(progress: Double, disease: LabDisease) {
        for leaf in leaves {
            let look = SymptomModel.appearance(for: disease.visual, plantProgress: progress, leafAge: leaf.age, leafIndex: leaf.index)
            leaf.blade.model?.materials = [palette.material(look.color)]
            for (index, lesion) in leaf.lesions.enumerated() {
                lesion.isEnabled = index < look.visibleLesions
            }
            for (index, halo) in leaf.halos.enumerated() {
                halo.isEnabled = index < look.visibleLesions && progress > 0.2
            }
            leaf.container.orientation = leaf.baseRotation * simd_quatf(angle: -look.curl, axis: [1, 0, 0])
            leaf.container.scale = SIMD3(repeating: look.scale)
        }
        // Severe disease causes fruit drop.
        for (index, fruit) in fruits.enumerated() {
            fruit.isEnabled = progress < 0.85 - Double(index) * 0.1
        }
    }

    func setPresentation(yaw: Float, zoom: Float) {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        // The sway system owns the turntable's rotation, so the user's yaw becomes its base.
        if var sway = turntable.components[SwayComponent.self] {
            sway.baseRotation = rotation
            turntable.components.set(sway)
        } else {
            turntable.orientation = rotation
        }
        root.scale = SIMD3(repeating: zoom)
    }

    // MARK: Inspection callout

    func attachCallout(_ entity: Entity) {
        callout = entity
        entity.components.set(BillboardComponent())
        entity.isEnabled = false
        root.addChild(entity)
    }

    /// Shows the callout above the tapped leaf, or hides it.
    func showCallout(above leafEntity: Entity?) {
        guard let callout else { return }
        guard let leafEntity else {
            callout.isEnabled = false
            return
        }
        let world = leafEntity.position(relativeTo: nil)
        callout.setPosition(world + [0, 0.09, 0.02], relativeTo: nil)
        callout.isEnabled = true
    }

    func leafComponent(for entity: Entity) -> LeafComponent? {
        entity.components[LeafComponent.self]
    }
}
