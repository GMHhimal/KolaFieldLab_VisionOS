//
//  FieldImmersiveView.swift
//  KolaFieldLab
//
//  Mixed-immersion outbreak field. The grid of plants reflects the simulation in
//  real time; rain falls when the scenario is wet; looking at a plant and pinching
//  sprays it. A floating scoreboard tracks day, losses, sprays and expected yield.
//

import RealityKit
import SwiftUI

struct FieldImmersiveView: View {
    @Environment(AppModel.self) private var model
    @State private var field = FieldScene()

    var body: some View {
        RealityView { content, attachments in
            field.build(size: model.fieldSize)
            content.add(field.root)
            if let board = attachments.entity(for: "scoreboard") {
                board.position = [0, 1.55, field.frontZ - Float(model.fieldSize) * field.spacing - 0.4]
                field.root.addChild(board)
            }
            field.apply(cells: model.simulation.cells, disease: model.selectedDisease, raining: model.weather.raining)
        } update: { _, _ in
            // Reading `revision` and `weather` registers them for observation, so this closure
            // re-runs whenever the simulation or weather changes.
            _ = model.revision
            field.apply(cells: model.simulation.cells, disease: model.selectedDisease, raining: model.weather.raining)
        } attachments: {
            Attachment(id: "scoreboard") {
                FieldScoreboard()
                    .environment(model)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let index = field.plantIndex(for: value.entity) else { return }
                    let success = model.treat(index)
                    field.pulse(index, success: success)
                }
        )
        .onAppear { model.immersiveSpaceState = .open }
        .onDisappear {
            model.pause()
            model.immersiveSpaceState = .closed
        }
    }
}

private struct FieldScoreboard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.simulation.stats
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.selectedDisease?.name ?? "Outbreak").font(.extraLargeTitle2)
                Spacer()
                Text("Day \(model.simulation.day)")
                    .font(.largeTitle.monospacedDigit())
                    .contentTransition(.numericText())
            }
            HStack(spacing: 24) {
                Stat(title: "Healthy", value: stats.healthy + stats.incubating, color: .green)
                Stat(title: "Infected", value: stats.infected, color: .orange)
                Stat(title: "Treated", value: stats.treated, color: .cyan)
                Stat(title: "Lost", value: stats.lost, color: .brown)
            }
            HStack {
                Label("\(model.simulation.spraysRemaining) sprays left", systemImage: "drop.triangle.fill")
                Spacer()
                Text("Expected yield \(stats.yieldIndex.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.title3.bold())
                    .foregroundStyle(stats.yieldIndex > 0.7 ? Color.green : Color.orange)
            }
            .font(.title3)
            if let last = model.lastTreatment, !last.success {
                Text("That plant can't be saved or you're out of sprays — consider removing it.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Text("Look at a plant and pinch to spray it. Infected plants above 70 % damage cannot be saved.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 720)
        .glassBackgroundEffect()
        .animation(.spring, value: model.simulation.day)
    }
}

private struct Stat: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(value)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(title).font(.headline).foregroundStyle(.secondary)
        }
    }
}
