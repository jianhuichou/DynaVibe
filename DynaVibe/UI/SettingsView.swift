// UI/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    // Use StateObject for the ViewModel if this view is creating/owning it,
    // or ObservedObject/EnvironmentObject if it's passed from a parent.
    @StateObject private var viewModel = AccelerationViewModel()
    
    // RateOption struct can remain as it's local to this View's Picker presentation logic
    struct RateOption: Hashable, Identifiable {
        let id: Int // The value stored in AppStorage (0 for Max)
        let label: String
    }

    let rateOptions: [RateOption] = [
        RateOption(id: 32, label: "32 Hz"),
        RateOption(id: 64, label: "64 Hz"),
        RateOption(id: 128, label: "128 Hz"),
        RateOption(id: 0, label: "Max") // 0 represents "Max"
    ]
    
    // Theme mode can remain local AppStorage or be moved to a separate AppearanceViewModel
    @AppStorage("themeMode") private var themeMode: Bool = false
    // useLinearAccelerationSetting is already in AccelerationViewModel, so remove local @AppStorage for it.

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Measurement Settings")) {
                    HStack {
                        Text("Sampling Rate")
                        Spacer()
                    }
                    // Bind to viewModel's @AppStorage-backed property
                    Picker("Sampling Rate", selection: $viewModel.samplingRateSettingStorage) {
                        ForEach(rateOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text("Recording Start Delay")
                    Stepper(value: $viewModel.recordingStartDelaySetting, in: 0...30, step: 1) {
                        Text("\(Int(viewModel.recordingStartDelaySetting)) seconds")
                    }

                    Text("Measurement Duration")
                    Stepper(value: $viewModel.measurementDurationSetting, in: 1...600, step: 1) {
                        Text(viewModel.autoStopRecordingEnabled ? "\(Int(viewModel.measurementDurationSetting)) seconds" : "Continuous (Manual Stop)")
                    }
                    .disabled(!viewModel.autoStopRecordingEnabled) // Use viewModel's property

                    Toggle("Auto-Stop After Duration", isOn: $viewModel.autoStopRecordingEnabled) // Use viewModel's property
                }
                
                Section(header: Text("Analysis Settings")) {
                    // Bind to viewModel's @AppStorage-backed property
                    Toggle("Subtract Gravity (Linear Acceleration)", isOn: $viewModel.useLinearAccelerationSetting)
                        .padding(.vertical, 4)

                    // Bind Picker directly to viewModel.selectedWeightingType
                    // The ViewModel's selectedWeightingType computed property handles AppStorage via selectedWeightingTypeStorage
                    Picker("Frequency Weighting", selection: $viewModel.selectedWeightingType) {
                        ForEach(WeightingType.allCases) { type in
                            Text(type.rawValue).tag(type) // Tag with the enum case itself
                        }
                    }
                    // No .onChange needed here as viewModel.selectedWeightingType's setter handles persistence.

                    Text("Applies frequency weighting to FFT results. Time-domain filter implementation is pending standard coefficients for RMS etc.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $themeMode)
                }
                
                Section(header: Text("About")) {
                    VStack {
                        Text("DynaVibe")
                            .font(.headline)
                        Text("Version 0.1.1")
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
