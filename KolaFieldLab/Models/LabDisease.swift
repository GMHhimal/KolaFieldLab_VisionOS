//
//  LabDisease.swift
//  KolaFieldLab
//
//  Diseases available in the spatial lab, with the visual and epidemiological
//  parameters used to render symptoms on the 3D specimen and to simulate spread.
//

import Foundation
import simd

/// How symptoms look on a leaf.
enum SymptomPattern: String, Codable, Sendable {
    /// Discrete lesions (optionally with a yellow halo and concentric rings).
    case spots
    /// Few large, irregular water-soaked patches.
    case blotches
    /// Light/dark green mottling.
    case mosaic
    /// Leaves cup, curl and shrink.
    case curl
}

/// RGB colour stored in JSON as [r, g, b] (0…1).
struct RGB: Codable, Hashable, Sendable {
    let r: Float, g: Float, b: Float

    init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        r = try container.decode(Float.self)
        g = try container.decode(Float.self)
        b = try container.decode(Float.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(r); try container.encode(g); try container.encode(b)
    }

    var simd: SIMD3<Float> { SIMD3(r, g, b) }

    func distance(to other: RGB) -> Float { simd_distance(simd, other.simd) }

    static func mix(_ a: RGB, _ b: RGB, _ t: Float) -> RGB {
        if t <= 0 { return a }
        if t >= 1 { return b }
        return RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    static let leafGreen = RGB(0.16, 0.52, 0.20)
}

struct VisualProfile: Codable, Hashable, Sendable {
    let pattern: SymptomPattern
    /// Colour the whole leaf drifts towards as the disease advances.
    let chlorosisColor: RGB
    let lesionColor: RGB
    let haloColor: RGB?
    /// Maximum lesions per leaf at the final stage.
    let maxLesions: Int
    /// Lesion radius in metres on the specimen.
    let lesionSize: Float
}

/// Epidemiological parameters for the outbreak simulator.
struct SpreadProfile: Codable, Hashable, Sendable {
    let minTemp: Double
    let maxTemp: Double
    /// Wet-weather disease: humidity at or above this (or rain) is ideal.
    let minHumidity: Double?
    /// Dry-weather vector (e.g. whiteflies): humidity at or below this is ideal.
    let maxHumidity: Double?
    /// Daily infection probability from one fully diseased neighbour in ideal weather.
    let transmission: Double
    /// Days between infection and visible symptoms.
    let incubationDays: Int
    /// Severity gained per day in ideal weather (1.0 = plant lost).
    let growthPerDay: Double
    /// Neighbourhood radius in plants (1 = touching neighbours, 2 = wind/vector-borne).
    let radius: Int
}

struct LabDisease: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let pathogen: String
    let kind: String
    let summary: String
    /// Four descriptions, from first symptoms to final stage.
    let stages: [String]
    let controls: [String]
    let visual: VisualProfile
    let spread: SpreadProfile

    func stageDescription(for progress: Double) -> String {
        guard !stages.isEmpty else { return "" }
        let index = min(stages.count - 1, max(0, Int(progress * Double(stages.count))))
        return stages[index]
    }

    func stageNumber(for progress: Double) -> Int {
        progress <= 0.001 ? 0 : min(stages.count, Int(progress * Double(stages.count)) + 1)
    }
}

struct LabCatalog {
    static let shared = LabCatalog()

    let diseases: [LabDisease]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "lab-diseases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LabDisease].self, from: data) else {
            diseases = []
            return
        }
        diseases = decoded
    }

    init(diseases: [LabDisease]) { self.diseases = diseases }

    func disease(id: String?) -> LabDisease? {
        guard let id else { return diseases.first }
        return diseases.first { $0.id == id } ?? diseases.first
    }
}
