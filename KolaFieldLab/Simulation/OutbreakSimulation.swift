//
//  OutbreakSimulation.swift
//  KolaFieldLab
//
//  A deterministic, testable model of how a disease moves through a field.
//  Each plant is a cell in a grid running a compartment model
//  (healthy → incubating → infected → lost, with treatment as an intervention).
//  Infection pressure comes from diseased neighbours within the pathogen's
//  dispersal radius and is scaled by how well today's weather suits the pathogen.
//

import Foundation

/// Reproducible pseudo-random numbers (SplitMix64) so a scenario replays identically.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct FieldWeather: Equatable, Sendable {
    var temperature: Double = 22
    var humidity: Double = 85
    var raining = false
}

enum PlantState: Equatable, Sendable {
    case healthy
    case incubating(daysLeft: Int)
    case infected(severity: Double)
    /// Treated plants recover gradually and are protected from re-infection.
    case treated(severity: Double)
    case lost

    /// 0 = healthy … 1 = dead; drives the 3D visuals.
    var visualSeverity: Double {
        switch self {
        case .healthy, .incubating: 0
        case .infected(let severity), .treated(let severity): severity
        case .lost: 1
        }
    }

    var isInfectious: Bool {
        if case .infected = self { return true }
        return false
    }

    /// Still able to change on its own (the outbreak is not over while any plant is active).
    var isActive: Bool {
        switch self {
        case .incubating, .infected: true
        default: false
        }
    }
}

struct OutbreakStats: Equatable, Sendable {
    var healthy = 0
    var incubating = 0
    var infected = 0
    var treated = 0
    var lost = 0
    /// Expected share of a full harvest (0…1).
    var yieldIndex: Double = 1

    var total: Int { healthy + incubating + infected + treated + lost }
}

struct OutbreakSimulation: Sendable {
    let size: Int
    private(set) var cells: [PlantState]
    private(set) var day = 0
    private(set) var spraysRemaining: Int
    private(set) var history: [OutbreakStats] = []
    private var rng: SplitMix64

    /// - Parameters:
    ///   - size: field is `size × size` plants.
    ///   - initialInfections: indices of plants infected on day 0 (defaults to one plant near the centre).
    ///   - sprays: treatment budget — makes the trainee prioritise.
    ///   - seed: RNG seed for reproducible scenarios.
    init(size: Int = 7, initialInfections: [Int]? = nil, sprays: Int = 8, seed: UInt64 = 2026) {
        self.size = size
        self.cells = Array(repeating: .healthy, count: size * size)
        self.spraysRemaining = sprays
        self.rng = SplitMix64(seed: seed)
        let seeds = initialInfections ?? [size * (size / 2) + size / 2 - 1]
        for index in seeds where cells.indices.contains(index) {
            cells[index] = .infected(severity: 0.25)
        }
        history = [stats]
    }

    // MARK: Geometry

    func index(row: Int, column: Int) -> Int { row * size + column }
    func position(of index: Int) -> (row: Int, column: Int) { (index / size, index % size) }

    func neighbours(of index: Int, radius: Int) -> [Int] {
        let (row, column) = position(of: index)
        var result: [Int] = []
        for r in max(0, row - radius)...min(size - 1, row + radius) {
            for c in max(0, column - radius)...min(size - 1, column + radius) where !(r == row && c == column) {
                result.append(self.index(row: r, column: c))
            }
        }
        return result
    }

    // MARK: Weather suitability

    /// 0…1 — how well the weather suits the pathogen (1 = ideal).
    static func weatherFactor(_ weather: FieldWeather, profile: SpreadProfile) -> Double {
        let temperature: Double
        if weather.temperature < profile.minTemp {
            temperature = max(0, 1 - (profile.minTemp - weather.temperature) / 6)
        } else if weather.temperature > profile.maxTemp {
            temperature = max(0, 1 - (weather.temperature - profile.maxTemp) / 6)
        } else {
            temperature = 1
        }

        var moisture = 1.0
        if let minHumidity = profile.minHumidity {
            moisture = weather.raining ? 1 : min(1, max(0, (weather.humidity - (minHumidity - 35)) / 35))
        } else if let maxHumidity = profile.maxHumidity {
            moisture = weather.raining ? 0.25 : min(1, max(0, (maxHumidity + 35 - weather.humidity) / 35))
        }
        return temperature * moisture
    }

    // MARK: Step

    mutating func step(weather: FieldWeather, profile: SpreadProfile) {
        let factor = Self.weatherFactor(weather, profile: profile)
        let snapshot = cells
        var next = cells

        for index in snapshot.indices {
            switch snapshot[index] {
            case .healthy:
                // Pressure from every infectious neighbour, weighted by its severity.
                let pressure = neighbours(of: index, radius: profile.radius)
                    .reduce(0.0) { sum, neighbour in
                        if case .infected(let severity) = snapshot[neighbour] { return sum + severity }
                        return sum
                    }
                guard pressure > 0 else { continue }
                let perContact = min(0.95, profile.transmission * factor)
                let probability = 1 - pow(1 - perContact, pressure)
                if Double.random(in: 0..<1, using: &rng) < probability {
                    next[index] = .incubating(daysLeft: max(1, profile.incubationDays))
                }
            case .incubating(let daysLeft):
                next[index] = daysLeft <= 1 ? .infected(severity: 0.1) : .incubating(daysLeft: daysLeft - 1)
            case .infected(let severity):
                // Disease keeps progressing slowly even in poor weather.
                let grown = severity + profile.growthPerDay * max(0.25, factor)
                next[index] = grown >= 1 ? .lost : .infected(severity: grown)
            case .treated(let severity):
                next[index] = .treated(severity: max(0, severity - 0.12))
            case .lost:
                break
            }
        }

        cells = next
        day += 1
        history.append(stats)
    }

    // MARK: Interventions

    /// Applies a spray to one plant. Infected plants beyond 70 % severity cannot be saved.
    @discardableResult
    mutating func treat(_ index: Int) -> Bool {
        guard spraysRemaining > 0, cells.indices.contains(index) else { return false }
        switch cells[index] {
        case .healthy:
            cells[index] = .treated(severity: 0)          // preventive spray
        case .incubating:
            cells[index] = .treated(severity: 0.05)
        case .infected(let severity) where severity < 0.7:
            cells[index] = .treated(severity: severity)
        default:
            return false
        }
        spraysRemaining -= 1
        if !history.isEmpty { history[history.count - 1] = stats }
        return true
    }

    /// Removes a plant (roguing) — stops it infecting others but loses its yield.
    mutating func rogue(_ index: Int) {
        guard cells.indices.contains(index) else { return }
        cells[index] = .lost
        if !history.isEmpty { history[history.count - 1] = stats }
    }

    // MARK: Statistics

    var stats: OutbreakStats {
        var stats = OutbreakStats()
        var harvest = 0.0
        for cell in cells {
            switch cell {
            case .healthy:
                stats.healthy += 1
                harvest += 1
            case .incubating:
                stats.incubating += 1
                harvest += 1
            case .infected(let severity):
                stats.infected += 1
                harvest += 1 - severity
            case .treated(let severity):
                stats.treated += 1
                harvest += 1 - severity * 0.5
            case .lost:
                stats.lost += 1
            }
        }
        stats.yieldIndex = cells.isEmpty ? 0 : harvest / Double(cells.count)
        return stats
    }

    var isOver: Bool { !cells.contains(where: \.isActive) }
}
