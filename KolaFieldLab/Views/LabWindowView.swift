//
//  LabWindowView.swift
//  KolaFieldLab
//
//  The main window: pick a disease, read how it develops, open the 3D specimen,
//  and run an outbreak scenario in the immersive field.
//

import Charts
import SwiftUI

struct LabWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(model.catalog.diseases, selection: $model.selectedDiseaseID) { disease in
                VStack(alignment: .leading, spacing: 4) {
                    Text(disease.name).font(.headline)
                    Text("\(disease.kind) · \(disease.pathogen)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Field Lab")
        } detail: {
            if let disease = model.selectedDisease {
                DiseaseDetailPane(disease: disease,
                                  openSpecimen: { openWindow(id: SceneID.specimen, value: disease.id) },
                                  toggleField: { Task { await toggleField() } })
            } else {
                ContentUnavailableView("Choose a disease", systemImage: "leaf")
            }
        }
        .onChange(of: model.selectedDiseaseID) { _, _ in model.resetSimulation() }
    }

    private func toggleField() async {
        switch model.immersiveSpaceState {
        case .open:
            model.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
            model.immersiveSpaceState = .closed
        case .closed:
            model.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: SceneID.field) {
            case .opened:
                model.immersiveSpaceState = .open
            case .userCancelled, .error:
                model.immersiveSpaceState = .closed
            @unknown default:
                model.immersiveSpaceState = .closed
            }
        case .inTransition:
            break
        }
    }
}

private struct DiseaseDetailPane: View {
    let disease: LabDisease
    var openSpecimen: () -> Void
    var toggleField: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it develops").font(.title3.bold())
                        ForEach(Array(disease.stages.enumerated()), id: \.offset) { index, stage in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .frame(width: 32, height: 32)
                                    .background(.green.opacity(0.25 + Double(index) * 0.15), in: Circle())
                                Text(stage)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Control measures").font(.title3.bold())
                        ForEach(disease.controls, id: \.self) { control in
                            Label(control, systemImage: "checkmark.shield")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24))
                }

                if model.immersiveSpaceState == .open {
                    SimulationControlsView()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(32)
            .animation(.spring, value: model.immersiveSpaceState)
        }
        .navigationTitle(disease.name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(disease.pathogen).font(.title3).italic().foregroundStyle(.secondary)
            Text(disease.summary).font(.title3)
            HStack(spacing: 16) {
                Button(action: openSpecimen) {
                    Label("Open 3D specimen", systemImage: "cube.transparent")
                }
                .buttonStyle(.borderedProminent)

                Button(action: toggleField) {
                    Label(model.immersiveSpaceState == .open ? "Leave the field" : "Enter outbreak field",
                          systemImage: model.immersiveSpaceState == .open ? "xmark.circle" : "square.grid.3x3.topleft.filled")
                }
                .disabled(model.immersiveSpaceState == .inTransition)
            }
            .controlSize(.extraLarge)
        }
    }
}
