//
//  Components.swift
//  KolaFieldLab
//
//  RealityKit Entity-Component-System pieces: data components attached to
//  entities, and systems that update them every frame on the render loop.
//

import RealityKit
import simd

/// Identifies a leaf on the 3D specimen (for tap-to-inspect).
struct LeafComponent: Component {
    let branch: Int
    let position: Int
    /// 0 = oldest/lowest leaf … 1 = youngest/top leaf. Symptoms start on old leaves.
    let age: Float
}

/// Identifies a plant in the immersive field grid (for tap-to-treat).
struct FieldPlantComponent: Component {
    let index: Int
}

/// Gentle wind sway around the entity's base.
struct SwayComponent: Component {
    var phase: Float
    var amplitude: Float
    var speed: Float = 1.4
    var elapsed: Float = 0
    var baseRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
}

/// A falling rain drop that loops back to the sky.
struct RainDropComponent: Component {
    var speed: Float
    var top: Float
}

final class SwaySystem: System {
    private static let query = EntityQuery(where: .has(SwayComponent.self))

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let delta = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var sway = entity.components[SwayComponent.self] else { continue }
            sway.elapsed += delta
            let angle = sin(sway.elapsed * sway.speed + sway.phase) * sway.amplitude
            entity.transform.rotation = sway.baseRotation * simd_quatf(angle: angle, axis: [0, 0, 1])
            entity.components[SwayComponent.self] = sway
        }
    }
}

final class RainSystem: System {
    private static let query = EntityQuery(where: .has(RainDropComponent.self))

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let delta = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard entity.isEnabled, let drop = entity.components[RainDropComponent.self] else { continue }
            var position = entity.position
            position.y -= drop.speed * delta
            if position.y < 0 { position.y = drop.top }
            entity.position = position
        }
    }
}

enum FieldLabECS {
    /// Must run once before any RealityView is created.
    static func register() {
        LeafComponent.registerComponent()
        FieldPlantComponent.registerComponent()
        SwayComponent.registerComponent()
        RainDropComponent.registerComponent()
        SwaySystem.registerSystem()
        RainSystem.registerSystem()
    }
}
