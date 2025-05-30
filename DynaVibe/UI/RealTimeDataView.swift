// UI/RealTimeDataView.swift
import SwiftUI

struct RealTimeDataView: View {
    @StateObject private var vm = AccelerationViewModel()
    // Renaming DisplayMode to GraphDomainType for clarity with new TimeDataType
    private enum GraphDomainType: String, CaseIterable, Identifiable {
        case time = "Time Domain"
        case frequency = "Frequency Domain"
        var id: String { self.rawValue }
    }
    @State private var currentGraphDomain: GraphDomainType = .time
    private let axisColors: [Axis: Color] = [.x: .red, .y: .green, .z: .blue]

    private var graphPlotData: [IdentifiableGraphPoint] {
        if currentGraphDomain == .time {
            return vm.currentGraphTimeData // Use the new computed property from ViewModel
        } else { // Frequency domain
            var points: [IdentifiableGraphPoint] = []
            guard vm.isFFTReady, !vm.fftFrequencies.isEmpty else { return [] }
            let sortedActiveAxes = vm.activeAxes.sorted(by: { $0.rawValue < $1.rawValue })
            for axisCase in sortedActiveAxes {
                if let magnitudes = vm.fftMagnitudes[axisCase], magnitudes.count == vm.fftFrequencies.count {
                    for i in 0..<vm.fftFrequencies.count {
                        points.append(IdentifiableGraphPoint(axis: axisCase, xValue: vm.fftFrequencies[i], yValue: magnitudes[i]))
                    }
                }
            }
            return points
        }
    }
    
    private var currentGraphRanges: MultiLineGraphView.AxisRanges {
        if currentGraphDomain == .time { // Use new GraphDomainType
            // Adjust X-axis range based on whether weighted data (which starts at t=0) or raw data (original timestamps) is shown
            var minXRange: Double = 0
            var maxXRange: Double = vm.currentEffectiveMaxGraphDuration

            if vm.displayTimeDataType == .raw, let firstTimestamp = vm.timeSeriesData.values.compactMap({ $0.first?.timestamp }).min() {
                 // For raw data, if not empty, minX might not be 0 if data is from a continued recording (not handled yet)
                 // or if timestamps are not relative to 0. For now, assume raw data timestamps start near 0 for simplicity.
                 // If using absolute timestamps, this would need adjustment.
                 // The current vm.axisRanges is probably better for raw data during/after recording.
            }

            if vm.measurementState == .recording && vm.displayTimeDataType == .weighted {
                // If live weighted view was possible and timestamps were relative to start of current segment
                maxXRange = vm.elapsedTime + 0.2 // Show a bit ahead
                if !vm.autoStopRecordingEnabled || vm.measurementDurationSetting <= 0 { // Manual stop or continuous
                     minXRange = max(0, vm.elapsedTime - 10.0) // 10s window
                }
            } else if vm.measurementState == .idle && vm.displayTimeDataType == .raw {
                 minXRange = 0
                 maxXRange = vm.currentEffectiveMaxGraphDuration
            } else if vm.measurementState == .idle && vm.displayTimeDataType == .weighted {
                // Show full potential duration for weighted if idle, assuming it might be populated from a previous run
                 minXRange = 0
                 // maxXRange could be based on the longest weighted series length / sampleRate if available
                 // For now, stick to currentEffectiveMaxGraphDuration or a default
                 let weightedDuration = Double(vm.weightedTimeSeriesX.count) / (vm.calculatedActualAverageSamplingRateForFFT ?? Double(vm.actualCoreMotionRequestRate))
                 maxXRange = (weightedDuration > 0) ? max(weightedDuration, 1.0) : vm.currentEffectiveMaxGraphDuration
            }
            else if vm.measurementState == .completed && vm.displayTimeDataType == .weighted {
                let weightedDuration = Double(vm.weightedTimeSeriesX.count) / (vm.calculatedActualAverageSamplingRateForFFT ?? Double(vm.actualCoreMotionRequestRate))
                minXRange = 0
                maxXRange = (weightedDuration > 0) ? max(weightedDuration, 1.0) : vm.currentEffectiveMaxGraphDuration
            }


            // Use vm.axisRanges for dynamic Y scaling during raw recording, but allow overrides for weighted/idle
            var finalMinY = vm.axisRanges.minY
            var finalMaxY = vm.axisRanges.maxY
            if vm.measurementState == .idle || vm.displayTimeDataType == .weighted {
                 finalMinY = -1.0 // Default for weighted or idle raw
                 finalMaxY = 1.0  // Default for weighted or idle raw
                if vm.displayTimeDataType == .weighted {
                    let allWeightedValues = (vm.weightedTimeSeriesX + vm.weightedTimeSeriesY + vm.weightedTimeSeriesZ).filter { $0.isFinite }
                    if let maxAbs = allWeightedValues.map(abs).max(), maxAbs > 0 {
                        finalMinY = -maxAbs
                        finalMaxY = maxAbs
                    } else if allWeightedValues.isEmpty && vm.measurementState == .completed { // No weighted data, but completed
                        finalMinY = -0.1; finalMaxY = 0.1 // Indicate no data effectively
                    }
                }
            }
             if vm.measurementState == .idle && vm.displayTimeDataType == .raw {
                 minXRange = 0; maxXRange = vm.currentEffectiveMaxGraphDuration
                 finalMinY = -1; finalMaxY = 1
             }


            return vm.measurementState == .recording && vm.displayTimeDataType == .raw ?
                   vm.axisRanges : // Use dynamic ranges from ViewModel for live raw data
                   MultiLineGraphView.AxisRanges(minY: finalMinY, maxY: finalMaxY, minX: minXRange, maxX: maxXRange)


        } else { // Frequency Domain
            let relevantRate = vm.calculatedActualAverageSamplingRateForFFT ?? Double(vm.actualCoreMotionRequestRate)
            let firstFreq = vm.fftFrequencies.first ?? 0.0
            let lastFreqPossible = relevantRate / 2.0
            let actualLastFreq = vm.fftFrequencies.last ?? lastFreqPossible
            let nyquist = max(firstFreq, actualLastFreq, 0.1) // Ensure nyquist is at least a small positive if freqs are empty
            
            guard vm.isFFTReady, !vm.fftFrequencies.isEmpty else {
                return MultiLineGraphView.AxisRanges(minY: 0, maxY: 1, minX: 0, maxX: max(1.0, nyquist))
            }
            
            var maxMagnitudeOverall: Double = 0.001
            vm.activeAxes.forEach { activeAxis in
                if let maxMagForAxis = vm.fftMagnitudes[activeAxis]?.filter({!$0.isNaN && $0.isFinite}).max(), maxMagForAxis > maxMagnitudeOverall {
                    maxMagnitudeOverall = maxMagForAxis
                }
            }
            if maxMagnitudeOverall <= 0.001 { // If still very small or zero
                 maxMagnitudeOverall = vm.fftMagnitudes.values.flatMap { $0 }.allSatisfy { $0 == 0 || $0.isNaN || !$0.isFinite } ? 0.1 : 1.0
            }

            let minXForFFT = firstFreq
            let maxXForFFT = max(minXForFFT + (nyquist > minXForFFT ? 0.1 : 1.0), nyquist)

            return MultiLineGraphView.AxisRanges(
                minY:0,
                maxY:maxMagnitudeOverall.isFinite && maxMagnitudeOverall > 0 ? maxMagnitudeOverall : 0.1,
                minX: minXForFFT,
                maxX: maxXForFFT
            )
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                MetricSummaryCard(
                    latestX: vm.latestX, latestY: vm.latestY, latestZ: vm.latestZ,
                    minX: vm.minX ?? 0.0, maxX: vm.maxX ?? 0.0,
                    minY: vm.minY ?? 0.0, maxY: vm.maxY ?? 0.0,
                    minZ: vm.minZ ?? 0.0, maxZ: vm.maxZ ?? 0.0,
                    rmsX: vm.measurementState == .completed ? vm.rmsX : nil,
                    rmsY: vm.measurementState == .completed ? vm.rmsY : nil,
                    rmsZ: vm.measurementState == .completed ? vm.rmsZ : nil
                    // TODO: Add weighted RMS to MetricSummaryCard if desired
                ).padding(.horizontal)

                Picker("Graph Domain", selection: $currentGraphDomain) {
                    ForEach(GraphDomainType.allCases) { domain in
                        Text(domain.rawValue).tag(domain)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if currentGraphDomain == .time {
                    Picker("Time Data Type", selection: $vm.displayTimeDataType) {
                        ForEach(AccelerationViewModel.TimeDataType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    // Disable if recording and weighted is selected, as weighted is post-processed
                    .disabled(vm.isRecording && vm.displayTimeDataType == .weighted)
                }


                HStack {
                    HStack(spacing: 8) {
                        Text("Axis:").font(.callout).foregroundColor(.secondary)
                        ForEach(Axis.allCases) { axisCase in Button(axisCase.rawValue.uppercased()) { Haptics.tap(); vm.toggleAxisVisibility(axisCase) }
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(vm.activeAxes.contains(axisCase) ? (axisColors[axisCase] ?? .accentColor).opacity(0.25) : Color(UIColor.systemGray5))
                                .foregroundColor(vm.activeAxes.contains(axisCase) ? (axisColors[axisCase] ?? .accentColor) : Color(UIColor.label).opacity(0.7))
                                .cornerRadius(7)
                        }
                    }.animation(.easeInOut(duration: 0.2), value: vm.activeAxes)
                    Spacer()
                    
                    if vm.measurementState == .preRecordingCountdown || (vm.isRecording && vm.autoStopRecordingEnabled && vm.measurementDurationSetting > 0) {
                        Text(String(format: "%.1f s", vm.timeLeft))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(vm.timeLeft < 5 && vm.timeLeft > 0 && vm.measurementState == .recording ? .red : .orange)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(UIColor.systemGray5).opacity(0.7)).cornerRadius(6)
                            .frame(minWidth: 60, alignment: .center)
                            .transition(.opacity.combined(with: .scale))
                    } else { Rectangle().fill(Color.clear).frame(minWidth: 60, maxWidth: 60) }
                    if vm.useLinearAccelerationSetting { Spacer(minLength: 10) }
                    
                    if vm.useLinearAccelerationSetting {
                        HStack(spacing: 6) { BubbleLevelView(roll: vm.currentRoll, pitch: vm.currentPitch)
                            VStack(alignment: .leading, spacing: 1) { Text(String(format: "R: %+.1f°", vm.currentRoll)); Text(String(format: "P: %+.1f°", vm.currentPitch))
                            }.font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        }.transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal).frame(height: 38)
                .animation(.default, value: vm.timeLeft)
                .animation(.easeInOut(duration: 0.3), value: vm.useLinearAccelerationSetting)
                .animation(.spring(response:0.3,dampingFraction:0.7), value:vm.currentRoll)
                .animation(.spring(response:0.3,dampingFraction:0.7), value:vm.currentPitch)

                HStack {
                    Text(String(format: "Rec Time: %.2f s", vm.elapsedTime)).font(.caption).foregroundColor(.secondary)
                    Spacer(); Text(vm.currentStatusText).id(vm.currentStatusText).font(.caption).foregroundColor(.secondary)
                    Spacer(); Text("Samples: \(vm.collectedSamplesCount)").font(.caption).foregroundColor(.secondary)
                }.padding(.horizontal)
                
                MultiLineGraphView(plotData: graphPlotData, ranges: currentGraphRanges,
                    isFrequencyDomain: currentGraphDomain == .frequency, axisColors: axisColors
                ).id("\(currentGraphDomain)-\(vm.displayTimeDataType)-\(vm.activeAxes.hashValue)-\(vm.measurementState.hashValue)-\(vm.isRecording)")
                // Added vm.displayTimeDataType to ID to force redraw on change

                HStack(spacing: 20) {
                    Button { Haptics.tap()
                        if vm.measurementState == .preRecordingCountdown || vm.isRecording { vm.stopMeasurement() }
                        else { vm.startMeasurement() }
                    } label: {
                        Label((vm.measurementState == .preRecordingCountdown || vm.isRecording) ? "Stop" : "Start",
                               systemImage: (vm.measurementState == .preRecordingCountdown || vm.isRecording) ? "stop.fill" : "play.fill")
                            .fontWeight(.medium).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint((vm.measurementState == .preRecordingCountdown || vm.isRecording) ? .red : .green).controlSize(.large)
                    .disabled(vm.measurementState == .completed && vm.collectedSamplesCount > 0 && !(vm.measurementState == .preRecordingCountdown || vm.isRecording) )

                    Button { Haptics.tap(); vm.resetMeasurement() }
                    label: { Label("Reset", systemImage: "arrow.clockwise").fontWeight(.medium).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(vm.measurementState == .preRecordingCountdown || vm.isRecording)
                }
                .padding([.horizontal, .bottom]).padding(.top, 5)
            }
            .navigationTitle("Real-Time Data").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Haptics.tap(); vm.exportCSV() }
                    label: { Image(systemName: "square.and.arrow.up") }
                    // Disable export if live recording/countdown, or if no data (unless it's idle and has previous data)
                    .disabled(vm.isRecording || vm.measurementState == .preRecordingCountdown || (vm.collectedSamplesCount == 0 && vm.measurementState != .idle && vm.measurementState != .completed) )
                }
            }
            .onChange(of: currentGraphDomain) { newDomain in
                if newDomain == .frequency && vm.measurementState == .completed && !vm.isFFTReady {
                     vm.computeFFT() // FFT computation might now use selectedWeightingType for spectrum weighting
                }
            }
            // Optional: onChange for vm.displayTimeDataType if any specific actions needed,
            // but graphPlotData will react automatically.
            .onAppear {
                 if vm.measurementState == .idle {
                     vm.timeLeft = vm.currentInitialTimeLeft
                     vm.axisRanges.maxX = vm.currentEffectiveMaxGraphDuration
                 }
                 if vm.useLinearAccelerationSetting { vm.startLiveAttitudeMonitoring() }
            }
            .onDisappear { vm.stopLiveAttitudeMonitoring() }
        }
        .navigationViewStyle(.stack)
    }
}
#Preview { RealTimeDataView() }
