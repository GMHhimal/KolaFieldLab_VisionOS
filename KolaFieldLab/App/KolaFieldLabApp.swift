//
//  KolaFieldLabApp.swift
//  KolaCare Field Lab — spatial crop-disease training for visionOS
//
//  Author: G M H Himal (IT23152632)
//  SE4041 Mobile Application Design and Development — Assignment 2, Part B
//
//  Three scene types work together:
//    • "lab"      – a window: disease guide, scenario controls and outbreak chart
//    • "specimen" – a volume: a life-size 3D plant whose symptoms advance on demand
//    • "field"    – an immersive space: a 7 × 7 tomato field on the user's floor
//                   where an outbreak spreads with the weather and trainees treat plants
//

import SwiftUI

@main
struct KolaFieldLabApp: App {
    @State private var model = AppModel()

    init() {
        FieldLabECS.register()
    }

    var body: some Scene {
        WindowGroup(id: SceneID.lab) {
            LabWindowView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)

        WindowGroup(id: SceneID.specimen, for: String.self) { $diseaseID in
            SpecimenVolumeView(diseaseID: diseaseID)
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.7, height: 0.8, depth: 0.7, in: .meters)

        ImmersiveSpace(id: SceneID.field) {
            FieldImmersiveView()
                .environment(model)
        }
        // Mixed immersion keeps the real room visible so the field sits on the user's floor.
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

enum SceneID {
    static let lab = "lab"
    static let specimen = "specimen"
    static let field = "field"
}
