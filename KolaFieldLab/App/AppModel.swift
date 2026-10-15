//
//  AppModel.swift
//  KolaFieldLab
//
//  Shared state for all scenes (lab window, specimen volume, immersive field):
//  the selected disease, the weather scenario and the running outbreak simulation.
//

import Foundation
import Observation

enum ImmersiveSpaceState: Equatable {
    case closed, inTransition, open
}

/// Ready-made weather scenarios drawn from Sri Lanka's growing seasons.
enum WeatherPreset: String, CaseIterable, Identifiable {
    case mahaMonsoon, yalaDrySpell, upCountryMist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mahaMonsoon: "Maha monsoon"
        case .yalaDrySpell: "Yala dry spell"
        case .upCountryMist: "Up-country mist"
        }
    }

    var detail: String {
        switch self {
        case .mahaMonsoon: "26 °C · 92 % · rain"
        case .yalaDrySpell: "32 °C · 55 % · dry"
        case .upCountryMist: "17 °C · 97 % · mist"
        }
    }

    var weather: FieldWeather {
        switch self {
        case .mahaMonsoon: FieldWeather(temperature: 26, humidity: 92, raining: true)
        case .yalaDrySpell: FieldWeather(temperature: 32, humidity: 55, raining: false)
        case .upCountryMist: FieldWeather(temperature: 17, humidity: 97, raining: false)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let catalog: LabCatalog
    let fieldSize = 7
    let sprayBudget = 8

    /// Views call `resetSimulation()` when this changes (see LabWindowView).
    var selectedDiseaseID: String?
    var weather = FieldWeather(temperature: 22, humidity: 90, raining: false)
    var daysPerSecond: Double = 1
    var immersiveSpaceState: ImmersiveSpaceState = .closed

    private(set) var simulation: OutbreakSimulation
    private(set) var isRunning = false
    /// Incremented on every visible change so RealityKit scenes know to refresh.
    private(set) var revision = 0
    /// Last plant the trainee tried to treat, with the outcome (for feedback in the field).
    private(set) var lastTreatment: (index: Int, success: Bool)?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var seed: UInt64 = 2026

    init(catalog: LabCatalog = .shared) {
        self.catalog = catalog
        self.selectedDiseaseID = catalog.diseases.first?.id
        self.simulation = OutbreakSimulation(size: fieldSize, sprays: sprayBudget, seed: seed)
    }

    var selectedDisease: LabDisease? { catalog.disease(id: selectedDiseaseID) }

    var weatherFactor: Double {
        guard let profile = selectedDisease?.spread else { return 0 }
        return OutbreakSimulation.weatherFactor(weather, profile: profile)
    }

    // MARK: Simulation control

    func play() {
        guard !isRunning, !simulation.isOver else { return }
        isRunning = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(1 / max(0.25, self.daysPerSecond)))
                guard !Task.isCancelled else { return }
                self.stepOnce()
                if self.simulation.isOver || self.simulation.day >= 60 { self.pause() }
            }
        }
    }

    func pause() {
        isRunning = false
        loop?.cancel()
        loop = nil
    }

    func stepOnce() {
        guard let profile = selectedDisease?.spread else { return }
        simulation.step(weather: weather, profile: profile)
        revision += 1
    }

    func resetSimulation(newSeed: Bool = false) {
        pause()
        if newSeed { seed = UInt64.random(in: 1...UInt64.max) }
        simulation = OutbreakSimulation(size: fieldSize, sprays: sprayBudget, seed: seed)
        lastTreatment = nil
        revision += 1
    }

    @discardableResult
    func treat(_ index: Int) -> Bool {
        let success = simulation.treat(index)
        lastTreatment = (index, success)
        revision += 1
        return success
    }

    func apply(_ preset: WeatherPreset) {
        weather = preset.weather
    }
}
