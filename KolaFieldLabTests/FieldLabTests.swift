//
//  FieldLabTests.swift
//  KolaFieldLabTests
//
//  The outbreak model and symptom rules are pure Swift, so they are verified
//  deterministically here without a headset.
//

import XCTest
@testable import KolaFieldLab

final class OutbreakSimulationTests: XCTestCase {
    private let lateBlight = SpreadProfile(minTemp: 10, maxTemp: 25, minHumidity: 90, maxHumidity: nil,
                                           transmission: 0.38, incubationDays: 2, growthPerDay: 0.16, radius: 2)
    private let whiteflyVirus = SpreadProfile(minTemp: 24, maxTemp: 36, minHumidity: nil, maxHumidity: 70,
                                              transmission: 0.2, incubationDays: 5, growthPerDay: 0.07, radius: 2)
    private let coolWet = FieldWeather(temperature: 18, humidity: 96, raining: true)
    private let hotDry = FieldWeather(temperature: 32, humidity: 50, raining: false)

    private func run(_ profile: SpreadProfile, weather: FieldWeather, days: Int, seed: UInt64 = 1) -> OutbreakSimulation {
        var simulation = OutbreakSimulation(size: 7, seed: seed)
        for _ in 0..<days { simulation.step(weather: weather, profile: profile) }
        return simulation
    }

    func testStartsWithOneInfectedPlant() {
        let simulation = OutbreakSimulation(size: 7)
        XCTAssertEqual(simulation.stats.infected, 1)
        XCTAssertEqual(simulation.stats.healthy, 48)
        XCTAssertEqual(simulation.history.count, 1)
    }

    func testSameSeedReplaysIdentically() {
        let a = run(lateBlight, weather: coolWet, days: 10, seed: 42)
        let b = run(lateBlight, weather: coolWet, days: 10, seed: 42)
        XCTAssertEqual(a.cells, b.cells)
    }

    func testFavourableWeatherSpreadsFasterThanUnfavourable() {
        let wet = run(lateBlight, weather: coolWet, days: 12)
        let dry = run(lateBlight, weather: hotDry, days: 12)
        XCTAssertGreaterThan(wet.stats.lost + wet.stats.infected, dry.stats.lost + dry.stats.infected)
        XCTAssertLessThan(wet.stats.yieldIndex, dry.stats.yieldIndex)
    }

    func testDryLovingVectorsReverseTheTrend() {
        let dry = run(whiteflyVirus, weather: hotDry, days: 20)
        let wet = run(whiteflyVirus, weather: coolWet, days: 20)
        XCTAssertGreaterThan(dry.stats.total - dry.stats.healthy, wet.stats.total - wet.stats.healthy)
    }

    func testStatsAlwaysAccountForEveryPlant() {
        var simulation = OutbreakSimulation(size: 7, seed: 9)
        for _ in 0..<25 {
            simulation.step(weather: coolWet, profile: lateBlight)
            XCTAssertEqual(simulation.stats.total, 49)
            XCTAssertTrue((0...1).contains(simulation.stats.yieldIndex))
        }
        XCTAssertEqual(simulation.history.count, 26)
        XCTAssertEqual(simulation.day, 25)
    }

    func testInfectedPlantIsEventuallyLost() {
        var simulation = OutbreakSimulation(size: 3, initialInfections: [4], seed: 3)
        for _ in 0..<10 { simulation.step(weather: coolWet, profile: lateBlight) }
        XCTAssertEqual(simulation.cells[4], .lost)
    }

    func testTreatmentSavesEarlyInfectionsAndUsesBudget() {
        var simulation = OutbreakSimulation(size: 3, initialInfections: [4], sprays: 2, seed: 3)
        XCTAssertTrue(simulation.treat(4))
        XCTAssertEqual(simulation.spraysRemaining, 1)
        guard case .treated = simulation.cells[4] else { return XCTFail("plant should be treated") }

        for _ in 0..<5 { simulation.step(weather: coolWet, profile: lateBlight) }
        XCTAssertEqual(simulation.cells[4], .treated(severity: 0), "treated plants recover fully")
        XCTAssertEqual(simulation.stats.lost, 0)
    }

    func testLateInfectionsCannotBeTreated() {
        var simulation = OutbreakSimulation(size: 3, initialInfections: [4], seed: 3)
        for _ in 0..<4 { simulation.step(weather: coolWet, profile: lateBlight) }   // severity ≈ 0.89
        XCTAssertFalse(simulation.treat(4))
        XCTAssertEqual(simulation.spraysRemaining, 8, "failed treatment does not consume a spray")
    }

    func testSprayBudgetIsEnforced() {
        var simulation = OutbreakSimulation(size: 3, initialInfections: [], sprays: 1)
        XCTAssertTrue(simulation.treat(0))
        XCTAssertFalse(simulation.treat(1))
    }

    func testRoguingStopsSpread() {
        var simulation = OutbreakSimulation(size: 7, seed: 5)
        let seedIndex = simulation.cells.firstIndex { $0.isInfectious }!
        simulation.rogue(seedIndex)
        for _ in 0..<15 { simulation.step(weather: coolWet, profile: lateBlight) }
        XCTAssertEqual(simulation.stats.lost, 1)
        XCTAssertEqual(simulation.stats.healthy, 48)
        XCTAssertTrue(simulation.isOver)
    }

    func testNeighbourhoodRespectsEdgesAndRadius() {
        let simulation = OutbreakSimulation(size: 7)
        XCTAssertEqual(simulation.neighbours(of: 0, radius: 1).count, 3, "corner")
        XCTAssertEqual(simulation.neighbours(of: 24, radius: 1).count, 8, "centre")
        XCTAssertEqual(simulation.neighbours(of: 24, radius: 2).count, 24)
    }

    func testWeatherFactorBounds() {
        XCTAssertEqual(OutbreakSimulation.weatherFactor(coolWet, profile: lateBlight), 1, accuracy: 0.0001)
        XCTAssertEqual(OutbreakSimulation.weatherFactor(FieldWeather(temperature: 40, humidity: 96, raining: true), profile: lateBlight), 0)
        let partial = OutbreakSimulation.weatherFactor(FieldWeather(temperature: 20, humidity: 75, raining: false), profile: lateBlight)
        XCTAssertGreaterThan(partial, 0)
        XCTAssertLessThan(partial, 1)
    }
}

final class SymptomModelTests: XCTestCase {
    private let spots = VisualProfile(pattern: .spots, chlorosisColor: RGB(0.8, 0.7, 0.2), lesionColor: RGB(0.3, 0.2, 0.1),
                                      haloColor: RGB(0.85, 0.78, 0.25), maxLesions: 8, lesionSize: 0.01)
    private let curl = VisualProfile(pattern: .curl, chlorosisColor: RGB(0.8, 0.8, 0.2), lesionColor: RGB(0.6, 0.6, 0.1),
                                     haloColor: nil, maxLesions: 0, lesionSize: 0)

    func testHealthyPlantLooksHealthy() {
        let look = SymptomModel.appearance(for: spots, plantProgress: 0, leafAge: 0, leafIndex: 0)
        XCTAssertEqual(look.visibleLesions, 0)
        XCTAssertEqual(look.color, .leafGreen)
        XCTAssertEqual(look.scale, 1)
    }

    func testOldLeavesShowSymptomsFirst() {
        let old = SymptomModel.localProgress(plantProgress: 0.4, leafAge: 0)
        let young = SymptomModel.localProgress(plantProgress: 0.4, leafAge: 1)
        XCTAssertGreaterThan(old, young)
        XCTAssertEqual(young, 0, "young leaves are still clean at 40 %")
    }

    func testLesionsIncreaseWithProgress() {
        let early = SymptomModel.appearance(for: spots, plantProgress: 0.2, leafAge: 0, leafIndex: 0)
        let late = SymptomModel.appearance(for: spots, plantProgress: 0.9, leafAge: 0, leafIndex: 0)
        XCTAssertLessThan(early.visibleLesions, late.visibleLesions)
        XCTAssertLessThanOrEqual(late.visibleLesions, spots.maxLesions)
    }

    func testCurlVirusCurlsAndShrinksLeaves() {
        let look = SymptomModel.appearance(for: curl, plantProgress: 1, leafAge: 0, leafIndex: 0)
        XCTAssertGreaterThan(look.curl, 0.5)
        XCTAssertLessThan(look.scale, 0.7)
        XCTAssertEqual(look.visibleLesions, 0)
    }

    func testFieldColourDarkensWithSeverityAndTreatmentHelps() {
        let healthy = SymptomModel.fieldColor(for: spots, severity: 0, treated: false)
        let dead = SymptomModel.fieldColor(for: spots, severity: 1, treated: false)
        XCTAssertEqual(healthy, .leafGreen)
        XCTAssertEqual(dead, MaterialPaletteColors.deadLeaf)
        let sick = SymptomModel.fieldColor(for: spots, severity: 0.4, treated: false)
        let treated = SymptomModel.fieldColor(for: spots, severity: 0.4, treated: true)
        XCTAssertLessThan(treated.distance(to: .leafGreen), sick.distance(to: .leafGreen), "treated plants look healthier")
    }
}

final class LabCatalogTests: XCTestCase {
    func testBundledDiseasesAreComplete() {
        let catalog = LabCatalog.shared
        XCTAssertEqual(catalog.diseases.count, 6)
        for disease in catalog.diseases {
            XCTAssertEqual(disease.stages.count, 4, disease.id)
            XCTAssertFalse(disease.controls.isEmpty, disease.id)
            XCTAssertGreaterThan(disease.spread.transmission, 0, disease.id)
        }
    }

    func testStageMapping() {
        let disease = LabCatalog.shared.diseases[0]
        XCTAssertEqual(disease.stageNumber(for: 0), 0)
        XCTAssertEqual(disease.stageNumber(for: 0.1), 1)
        XCTAssertEqual(disease.stageNumber(for: 1), 4)
        XCTAssertEqual(disease.stageDescription(for: 1), disease.stages[3])
    }
}
