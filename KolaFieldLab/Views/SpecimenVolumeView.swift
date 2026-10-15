//
//  SpecimenVolumeView.swift
//  KolaFieldLab
//
//  Volumetric window with a life-size plant. Look at a leaf and pinch to inspect
//  its symptoms; drag to turn the plant; scrub or play the disease timeline;
//  try a treatment and watch the plant recover.
//

import RealityKit
import SwiftUI

struct SpecimenVolumeView: View {
    let diseaseID: String?

    @Environment(AppModel.self) private var model
    @State private var controller = SpecimenController()
    @State private var progress: Double = 0.35
    @State private var yaw: Float = 0
    @State private var dragStartYaw: Float?
    @State private var zoom: Float = 1
    @State private var zoomStart: Float?
    @State private var inspectedLeaf: LeafComponent?
    @State private var playback: Task<Void, Never>?
    @State private var treating = false

    private var disease: LabDisease? { model.catalog.disease(id: diseaseID) }

    var body: some View {
        RealityView { content, attachments in
            controller.root.position = [0, -0.36, 0]           // sit the pot on the volume's floor
            content.add(controller.root)
            if let callout = attachments.entity(for: "callout") {
                controller.attachCallout(callout)
            }
            if let disease {
                controller.build(for: disease)
                controller.apply(progress: progress, disease: disease)
            }
        } update: { _, _ in
            guard let disease else { return }
            controller.build(for: disease)
            controller.apply(progress: progress, disease: disease)
            controller.setPresentation(yaw: yaw, zoom: zoom)
        } attachments: {
            Attachment(id: "callout") {
                if let leaf = inspectedLeaf, let disease {
                    LeafCallout(disease: disease, leaf: leaf, progress: progress) { inspectedLeaf = nil }
                }
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let leaf = controller.leafComponent(for: value.entity) {
                        inspectedLeaf = leaf
                        controller.showCallout(above: value.entity)
                    } else {
                        inspectedLeaf = nil
                        controller.showCallout(above: nil)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .targetedToAnyEntity()
                .onChanged { value in
                    if dragStartYaw == nil { dragStartYaw = yaw }
                    yaw = (dragStartYaw ?? 0) + Float(value.gestureValue.translation.width) * 0.01
                }
                .onEnded { _ in dragStartYaw = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if zoomStart == nil { zoomStart = zoom }
                    zoom = min(1.6, max(0.6, (zoomStart ?? 1) * Float(value.gestureValue.magnification)))
                }
                .onEnded { _ in zoomStart = nil }
        )
        .ornament(attachmentAnchor: .scene(.bottom)) {
            controls
        }
        .onDisappear { playback?.cancel() }
    }

    // MARK: Controls ornament

    private var controls: some View {
        VStack(spacing: 12) {
            if let disease {
                HStack {
                    Text(disease.name).font(.headline)
                    Spacer()
                    Text(stageLabel).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Image(systemName: "leaf").foregroundStyle(.green)
                    Slider(value: $progress, in: 0...1) {
                        Text("Disease stage")
                    }
                    .frame(width: 320)
                    .accessibilityValue(stageLabel)
                    Image(systemName: "leaf.fill").foregroundStyle(.brown)
                }
                HStack(spacing: 12) {
                    Button {
                        playProgression()
                    } label: {
                        Label("Watch it spread", systemImage: "play.fill")
                    }
                    Button {
                        treat()
                    } label: {
                        Label(treating ? "Recovering…" : "Apply treatment", systemImage: "drop.triangle")
                    }
                    .disabled(treating || progress < 0.05)
                    Button {
                        withAnimation { yaw = 0; zoom = 1 }
                    } label: {
                        Label("Reset view", systemImage: "arrow.uturn.backward")
                    }
                }
                if progress >= 0.75 && treating == false {
                    Text("At this stage treatment rarely saves the plant — remove it to protect neighbours.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .glassBackgroundEffect()
    }

    private var stageLabel: String {
        guard let disease else { return "" }
        let stage = disease.stageNumber(for: progress)
        return stage == 0 ? "Healthy" : "Stage \(stage) of \(disease.stages.count)"
    }

    // MARK: Animations

    private func playProgression() {
        playback?.cancel()
        progress = 0
        playback = Task { @MainActor in
            while progress < 1, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                progress = min(1, progress + 0.01)
            }
        }
    }

    /// Treatment works in early stages; late stages only slow down.
    private func treat() {
        playback?.cancel()
        treating = true
        let target = progress < 0.6 ? 0.04 : progress * 0.85
        playback = Task { @MainActor in
            while progress > target, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                progress = max(target, progress - 0.012)
            }
            treating = false
        }
    }
}

/// Floating card shown above an inspected leaf.
private struct LeafCallout: View {
    let disease: LabDisease
    let leaf: LeafComponent
    let progress: Double
    var onClose: () -> Void

    private var localProgress: Double {
        SymptomModel.localProgress(plantProgress: progress, leafAge: leaf.age)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(leaf.age < 0.3 ? "Old, lower leaf" : leaf.age > 0.7 ? "Young, upper leaf" : "Mid-canopy leaf")
                    .font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .buttonBorderShape(.circle)
            }
            if localProgress < 0.02 {
                Text("No symptoms yet on this leaf.").font(.callout)
            } else {
                Text(disease.stageDescription(for: localProgress)).font(.callout)
            }
            ProgressView(value: localProgress) {
                Text("Leaf damage").font(.caption)
            }
            .tint(localProgress > 0.6 ? .red : .orange)
        }
        .padding(16)
        .frame(width: 300)
        .glassBackgroundEffect()
    }
}
