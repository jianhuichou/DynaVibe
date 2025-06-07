// UI/SettingsView.swift
import SwiftUI

// Define the enum for acceleration units here for now.
// Ideally, this would be in a shared file if used by multiple views/viewmodels directly.
enum AccelerationUnit: String, CaseIterable, Identifiable {
    case metersPerSecondSquared = "m/s²"
    case gForce = "g"
    var id: String { self.rawValue }
}

struct SettingsView: View {
    @AppStorage("samplingRateSettingStorage") private var samplingRateSettingStorage: Int = 128
    
    struct RateOption: Hashable, Identifiable {
        let id: Int
        let label: String
    }

    let rateOptions: [RateOption] = [
        RateOption(id: 32, label: "32 Hz"),
        RateOption(id: 64, label: "64 Hz"),
        RateOption(id: 128, label: "128 Hz"),
        RateOption(id: 0, label: "Max")
    ]
    
    @AppStorage("measurementDurationSetting") private var measurementDuration: Double = 10.0
    @AppStorage("recordingStartDelaySetting") private var recordingStartDelay: Double = 3.0
    @AppStorage("autoStopRecordingEnabled") private var autoStopRecordingEnabled: Bool = true
    
    @AppStorage("themeMode") private var themeMode: Bool = false
    @AppStorage("useLinearAccelerationSetting") private var useLinearAcceleration: Bool = false

    // New AppStorage variable for acceleration unit
    @AppStorage("accelerationUnitSetting") private var accelerationUnit: AccelerationUnit = .metersPerSecondSquared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Measurement Settings")) {
                    HStack {
                        Text("Sampling Rate")
                        Spacer()
                    }
                    Picker("Sampling Rate", selection: $samplingRateSettingStorage) {
                        ForEach(rateOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text("Recording Start Delay")
                    Stepper(value: $recordingStartDelay, in: 0...30, step: 1) {
                        Text("\(Int(recordingStartDelay)) seconds")
                    }

                    Text("Measurement Duration")
                    Stepper(value: $measurementDuration, in: 1...600, step: 1) {
                        Text(autoStopRecordingEnabled ? "\(Int(measurementDuration)) seconds" : "Continuous (Manual Stop)")
                    }
                    .disabled(!autoStopRecordingEnabled)

                    Toggle("Auto-Stop After Duration", isOn: $autoStopRecordingEnabled)
                }
                
                Section(header: Text("Analysis Settings")) {
                    Toggle("Subtract Gravity (Linear Acceleration)", isOn: $useLinearAcceleration)
                        .padding(.vertical, 4)

                    // Picker for Acceleration Unit
                    Picker("Acceleration Unit", selection: $accelerationUnit) {
                        ForEach(AccelerationUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    // .pickerStyle(.segmented) // Optionally use segmented picker style
                }
                
                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $themeMode)
                }
                
                Section(header: Text("About")) {
                    VStack {
                        Text("DynaVibe")
                            .font(.headline)
                        Text("Version 0.1.1") // Example version
                            .font(.subheadline)
                        Text("Structural Dynamics & Vibration Analysis App")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 5)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    SettingsView()
}
