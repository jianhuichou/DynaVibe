// DynaVibe/UI/RealTimeDataView.swift
import SwiftUI

struct RealTimeDataView: View {
    @StateObject private var vm = AccelerationViewModel() // Ensure vm is @StateObject
    @State private var currentDisplayMode: GraphDisplayMode = .time // Default to time series
    
    enum GraphDisplayMode: String, CaseIterable, Identifiable {
        case time = "Time Series"
        case frequency = "Frequency Spectrum"
        var id: String { self.rawValue }
    }

    private var currentGraphRanges: MultiLineGraphView.AxisRanges {
        if currentDisplayMode == .time {
            // Use the dynamic ranges from the ViewModel for time series
            return vm.axisRanges
        } else {
            // Calculate ranges for frequency spectrum (FFT data)
            // Ensure there's a fallback if FFT data is empty or invalid
            let firstFreq = vm.fftFrequencies.first ?? 0
            let relevantRate = vm.calculatedActualAverageSamplingRateForFFT ?? (Double(vm.actualCoreMotionRequestRate) / 2.0) // Default to half of sampling rate if actual not available
            
            let lastFreqPossible = relevantRate / 2.0 // Nyquist frequency based on sampling rate
            let actualLastFreq = vm.fftFrequencies.last ?? lastFreqPossible // Use actual last freq if available, else theoretical max
            let nyquist = max(firstFreq, actualLastFreq, 0.1) // Ensure nyquist is at least a small positive value to avoid empty range

            // Determine overall max magnitude for Y-axis scaling
            var maxMagnitudeOverall: Double = 0.00000001 // Start with a very small epsilon to avoid zero if all magnitudes are zero

            if let xMags = vm.fftMagnitudes[Axis.x], !xMags.isEmpty {
                maxMagnitudeOverall = max(maxMagnitudeOverall, xMags.max() ?? 0)
            }
            if let yMags = vm.fftMagnitudes[Axis.y], !yMags.isEmpty {
                maxMagnitudeOverall = max(maxMagnitudeOverall, yMags.max() ?? 0)
            }
            if let zMags = vm.fftMagnitudes[Axis.z], !zMags.isEmpty {
                maxMagnitudeOverall = max(maxMagnitudeOverall, zMags.max() ?? 0)
            }

            // Ensure maxMagnitudeOverall is positive; if it's still the epsilon or less, default to 1.0
            if maxMagnitudeOverall <= 0.00000001 { maxMagnitudeOverall = 1.0 }


            return .init(minY: 0, maxY: maxMagnitudeOverall, minX: 0, maxX: nyquist)
        }
    }


    var body: some View {
        NavigationView {
            VStack(spacing: 0) { // Ensure no unintended spacing issues

                // Display Mode Picker
                Picker("Display Mode", selection: $currentDisplayMode) {
                    ForEach(GraphDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 8) // Add some vertical padding

                // Graph Area
                MultiLineGraphView(
                    timeSeriesData: vm.timeSeriesData,
                    fftFrequencies: vm.fftFrequencies,
                    fftMagnitudes: vm.fftMagnitudes,
                    axisRanges: currentGraphRanges, // Use the dynamic ranges
                    displayMode: currentDisplayMode,
                    activeAxes: vm.activeAxes // Pass activeAxes
                )
                .frame(maxHeight: 300) // Keep reasonable fixed height for graph
                .padding(.horizontal) // Add horizontal padding
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6))) // Subtle background
                .padding(.horizontal) // Padding for the background itself
                .padding(.bottom, 8) // Space before next element

                // Status Text Area
                HStack {
                    Text(vm.currentStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if vm.measurementState == .recording || vm.measurementState == .preRecordingCountdown {
                        Text("Time Left: \(vm.timeLeft, specifier: "%.1f")s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 100, alignment: .trailing) // Ensure width for time display
                    } else if vm.measurementState == .completed {
                         Text("Total Time: \(vm.elapsedTime, specifier: "%.2f")s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 100, alignment: .trailing)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4) // Minimal vertical padding for status

                // Metrics Summary (conditionally shown)
                if vm.measurementState == .completed && vm.collectedSamplesCount > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            MetricSummaryCard(title: "RMS X", value: vm.rmsX, unit: "g", peakFrequency: vm.peakFrequencyX)
                            MetricSummaryCard(title: "RMS Y", value: vm.rmsY, unit: "g", peakFrequency: vm.peakFrequencyY)
                            MetricSummaryCard(title: "RMS Z", value: vm.rmsZ, unit: "g", peakFrequency: vm.peakFrequencyZ)
                        }
                        .padding(.horizontal) // Horizontal padding for scroll content
                        .padding(.vertical, 4) // Some vertical padding around cards
                    }
                    .frame(height: 100) // Fixed height for summary cards area
                } else {
                    // Placeholder for consistent layout when summary cards are not shown
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 100)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                
                // Bubble Level (conditionally shown based on setting)
                if vm.useLinearAccelerationSetting {
                    BubbleLevelView(roll: vm.currentRoll, pitch: vm.currentPitch)
                        .frame(width: 100, height: 100) // Example fixed size
                        .padding(.vertical, 4) // Padding around bubble level
                }


                // Controls Area
                HStack(spacing: 10) { // Add spacing between buttons
                    Button(action: {
                        if vm.isRecording || vm.measurementState == .preRecordingCountdown {
                            Task { await vm.stopMeasurement() }
                        } else {
                            Task { await vm.startMeasurement() }
                        }
                    }) {
                        Text(vm.isRecording || vm.measurementState == .preRecordingCountdown ? "Stop" : "Start")
                            .frame(minWidth: 0, maxWidth: .infinity) // Make buttons expand
                            .padding()
                            .background(vm.isRecording || vm.measurementState == .preRecordingCountdown ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        Task { await vm.resetMeasurement() }
                    }) {
                        Text("Reset")
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(vm.isRecording || vm.measurementState == .preRecordingCountdown) // Disable if recording or counting down

                    Button(action: {
                        vm.exportCSV() // exportCSV is synchronous in ViewModel
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(vm.isRecording || vm.measurementState == .preRecordingCountdown || vm.collectedSamplesCount == 0)
                }
                .padding() // Padding around the HStack of buttons
                .background(Color(UIColor.systemGray5)) // Background for control area

            } // End Main VStack
            .navigationTitle("Real-Time Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { // Toolbar for axis toggles
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    HStack {
                        Text("Axes:").font(.caption)
                        Button(action: { vm.toggleAxisVisibility(.x) }) {
                            Text("X").foregroundColor(vm.activeAxes.contains(.x) ? .red : .gray)
                        }
                        Button(action: { vm.toggleAxisVisibility(.y) }) {
                            Text("Y").foregroundColor(vm.activeAxes.contains(.y) ? .green : .gray)
                        }
                        Button(action: { vm.toggleAxisVisibility(.z) }) {
                            Text("Z").foregroundColor(vm.activeAxes.contains(.z) ? .blue : .gray)
                        }
                    }
                }
            }
        } // End NavigationView
        .navigationViewStyle(StackNavigationViewStyle()) // Use stack style for consistent behavior
        .onChange(of: currentDisplayMode) { oldValue, newValue in // Updated onChange syntax
            if newValue == .frequency && vm.collectedSamplesCount > 0 && !vm.isFFTReady {
                // If switching to frequency view and FFT is not ready, compute it.
                Task { await vm.computeFFT() }
            }
        }
        .onAppear {
            // Assuming vm.startLiveAttitudeMonitoring is now async
            Task { await vm.startLiveAttitudeMonitoring() }
        }
        .onDisappear {
            // Assuming vm.stopLiveAttitudeMonitoring is now async
            // Based on previous changes, stopLiveAttitudeMonitoring was kept synchronous.
            // If it was made async, this needs `Task { await vm.stopLiveAttitudeMonitoring() }`
            // For now, assuming it's synchronous as per my last ViewModel output for this branch.
            // Update: Prompt says "assuming stopLiveAttitudeMonitoring ... is now the async version"
            Task { await vm.stopLiveAttitudeMonitoring() }
        }
    }
}

struct RealTimeDataView_Previews: PreviewProvider {
    static var previews: some View {
        RealTimeDataView()
    }
}
