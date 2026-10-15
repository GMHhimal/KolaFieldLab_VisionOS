//
//  SimulationControlsView.swift
//  KolaFieldLab
//
//  Weather scenario, playback and the outbreak curve. Shown in the lab window
//  while the immersive field is open, so the trainer can change conditions live.
//

import Charts
import SwiftUI

struct SimulationControlsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Outbreak scenario").font(.title3.bold())
                Spacer()
                Text("Day \(model.simulation.day)")
                    .font(.title3.monospacedDigit())
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                ForEach(WeatherPreset.allCases) { preset in
                    Button {
                        model.apply(preset)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(preset.title).font(.headline)
                            Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Label("Temperature", systemImage: "thermometer.medium")
                    Slider(value: $model.weather.temperature, in: 10...38, step: 1)
                    Text("\(Int(model.weather.temperature)) °C").monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                GridRow {
                    Label("Humidity", systemImage: "humidity")
                    Slider(value: $model.weather.humidity, in: 30...100, step: 1)
                    Text("\(Int(model.weather.humidity)) %").monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                GridRow {
                    Label("Rain", systemImage: "cloud.rain")
                    Toggle("Rain", isOn: $model.weather.raining).labelsHidden()
                    Text(model.weatherFactor, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(model.weatherFactor > 0.6 ? Color.red : Color.secondary)
                        .frame(width: 70, alignment: .trailing)
                        .help("How well today's weather suits this disease")
                }
            }

            HStack(spacing: 12) {
                Button {
                    if model.isRunning { model.pause() } else { model.play() }
                } label: {
                    Label(model.isRunning ? "Pause" : "Run", systemImage: model.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.simulation.isOver && !model.isRunning)

                Button { model.stepOnce() } label: { Label("Next day", systemImage: "forward.frame") }
                    .disabled(model.isRunning)
                Button { model.resetSimulation(newSeed: true) } label: { Label("New outbreak", systemImage: "arrow.counterclockwise") }

                Spacer()
                Picker("Speed", selection: $model.daysPerSecond) {
                    Text("1 day/s").tag(1.0)
                    Text("2 days/s").tag(2.0)
                    Text("4 days/s").tag(4.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            OutbreakChart(history: model.simulation.history)
                .frame(height: 200)
        }
        .padding(24)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
    }
}

struct OutbreakChart: View {
    let history: [OutbreakStats]

    private struct Point: Identifiable {
        let day: Int
        let series: String
        let value: Int
        var id: String { "\(day)-\(series)" }
    }

    private var points: [Point] {
        history.enumerated().flatMap { day, stats in
            [Point(day: day, series: "Healthy", value: stats.healthy + stats.incubating),
             Point(day: day, series: "Infected", value: stats.infected),
             Point(day: day, series: "Treated", value: stats.treated),
             Point(day: day, series: "Lost", value: stats.lost)]
        }
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Day", point.day), y: .value("Plants", point.value))
                .foregroundStyle(by: .value("Status", point.series))
        }
        .chartForegroundStyleScale(["Healthy": Color.green, "Infected": Color.orange, "Treated": Color.cyan, "Lost": Color.brown])
        .chartXAxisLabel("Day")
        .chartYAxisLabel("Plants")
        .accessibilityLabel("Outbreak curve")
    }
}
