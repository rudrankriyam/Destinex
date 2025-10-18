//
//  SettingsView.swift
//  MLXDestinex
//
//  Created by Rudrank Riyam on 10/18/25.
//

import SwiftUI

// MARK: - App Settings Manager
@MainActor
class AppSettings: ObservableObject {
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Int = 512
    @Published var topP: Double = 0.9
    @Published var repetitionPenalty: Double = 1.1

    // Tool toggles
    @Published var weatherToolEnabled: Bool = true
    @Published var webSearchToolEnabled: Bool = false
    @Published var calculationToolEnabled: Bool = true

    // Model preferences
    @Published var selectedModel: String = "mlx-community/Qwen3-1.7B-4bit"
    @Published var autoLoadModel: Bool = true

    private let userDefaults = UserDefaults.standard

    // Keys for UserDefaults
    private enum Keys {
        static let temperature = "temperature"
        static let maxTokens = "maxTokens"
        static let topP = "topP"
        static let repetitionPenalty = "repetitionPenalty"
        static let weatherToolEnabled = "weatherToolEnabled"
        static let webSearchToolEnabled = "webSearchToolEnabled"
        static let calculationToolEnabled = "calculationToolEnabled"
        static let selectedModel = "selectedModel"
        static let autoLoadModel = "autoLoadModel"
    }

    init() {
        loadSettings()
    }

    // MARK: - Save and Load
    func saveSettings() {
        userDefaults.set(temperature, forKey: Keys.temperature)
        userDefaults.set(maxTokens, forKey: Keys.maxTokens)
        userDefaults.set(topP, forKey: Keys.topP)
        userDefaults.set(repetitionPenalty, forKey: Keys.repetitionPenalty)
        userDefaults.set(weatherToolEnabled, forKey: Keys.weatherToolEnabled)
        userDefaults.set(webSearchToolEnabled, forKey: Keys.webSearchToolEnabled)
        userDefaults.set(calculationToolEnabled, forKey: Keys.calculationToolEnabled)
        userDefaults.set(selectedModel, forKey: Keys.selectedModel)
        userDefaults.set(autoLoadModel, forKey: Keys.autoLoadModel)
    }

    private func loadSettings() {
        temperature = userDefaults.double(forKey: Keys.temperature)
        maxTokens = userDefaults.integer(forKey: Keys.maxTokens)
        topP = userDefaults.double(forKey: Keys.topP)
        repetitionPenalty = userDefaults.double(forKey: Keys.repetitionPenalty)
        weatherToolEnabled = userDefaults.bool(forKey: Keys.weatherToolEnabled)
        webSearchToolEnabled = userDefaults.bool(forKey: Keys.webSearchToolEnabled)
        calculationToolEnabled = userDefaults.bool(forKey: Keys.calculationToolEnabled)
        selectedModel = userDefaults.string(forKey: Keys.selectedModel) ?? "mlx-community/Qwen3-1.7B-4bit"
        autoLoadModel = userDefaults.bool(forKey: Keys.autoLoadModel)

        // Set defaults if no values exist
        if temperature == 0 { temperature = 0.7 }
        if maxTokens == 0 { maxTokens = 512 }
        if topP == 0 { topP = 0.9 }
        if repetitionPenalty == 0 { repetitionPenalty = 1.1 }
    }

    // MARK: - Reset to Defaults
    func resetToDefaults() {
        temperature = 0.7
        maxTokens = 512
        topP = 0.9
        repetitionPenalty = 1.1

        weatherToolEnabled = true
        webSearchToolEnabled = false
        calculationToolEnabled = true

        selectedModel = "mlx-community/Qwen3-1.7B-4bit"
        autoLoadModel = true

        saveSettings()
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var settings = AppSettings()
    @State private var showingResetAlert = false

    var body: some View {
        NavigationView {
            Form {
                // Generation Parameters Section
                Section("Generation Parameters") {
                    ParameterSliderView(
                        title: "Temperature",
                        value: $settings.temperature,
                        range: 0.0...1.0,
                        description: "Controls randomness. Higher = more creative"
                    )

                    ParameterSliderView(
                        title: "Max Tokens",
                        value: Binding(
                            get: { Double(settings.maxTokens) },
                            set: { settings.maxTokens = Int($0) }
                        ),
                        range: 64...2048,
                        step: 64,
                        description: "Maximum response length"
                    )

                    ParameterSliderView(
                        title: "Top-P",
                        value: $settings.topP,
                        range: 0.0...1.0,
                        description: "Nucleus sampling threshold"
                    )

                    ParameterSliderView(
                        title: "Repetition Penalty",
                        value: $settings.repetitionPenalty,
                        range: 1.0...2.0,
                        description: "Discourages repetitive content"
                    )
                }

                // Tools Section
                Section("Tools") {
                    ToggleView(
                        title: "Weather Tool",
                        subtitle: "Get current weather information",
                        isOn: $settings.weatherToolEnabled
                    )

                    ToggleView(
                        title: "Web Search",
                        subtitle: "Search the web for information",
                        isOn: $settings.webSearchToolEnabled
                    )

                    ToggleView(
                        title: "Calculator",
                        subtitle: "Perform mathematical calculations",
                        isOn: $settings.calculationToolEnabled
                    )
                }

                
                // Model Settings Section
                Section("Model Settings") {
                    Picker("Selected Model", selection: $settings.selectedModel) {
                        Text("Qwen3 1.7B (4-bit)").tag("mlx-community/Qwen3-1.7B-4bit")
                        Text("Qwen3 0.5B (4-bit)").tag("mlx-community/Qwen3-0.5B-4bit")
                        Text("Mistral 7B (4-bit)").tag("mlx-community/Mistral-7B-Instruct-v0.3-4bit")
                    }

                    ToggleView(
                        title: "Auto-load Model",
                        subtitle: "Automatically load model on app launch",
                        isOn: $settings.autoLoadModel
                    )
                }

                // Reset Section
                Section {
                    Button("Reset to Defaults") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
        }
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        .onChange(of: settings.temperature) { _ in settings.saveSettings() }
        .onChange(of: settings.maxTokens) { _ in settings.saveSettings() }
        .onChange(of: settings.topP) { _ in settings.saveSettings() }
        .onChange(of: settings.repetitionPenalty) { _ in settings.saveSettings() }
        .onChange(of: settings.weatherToolEnabled) { _ in settings.saveSettings() }
        .onChange(of: settings.webSearchToolEnabled) { _ in settings.saveSettings() }
        .onChange(of: settings.calculationToolEnabled) { _ in settings.saveSettings() }
        .onChange(of: settings.selectedModel) { _ in settings.saveSettings() }
        .onChange(of: settings.autoLoadModel) { _ in settings.saveSettings() }
    }
}

// MARK: - Parameter Slider View
struct ParameterSliderView: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.monospaced(.body)())
                    .foregroundColor(.secondary)
            }

            Slider(value: $value, in: range, step: step) {
                Text(description)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Toggle View
struct ToggleView: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $isOn)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}