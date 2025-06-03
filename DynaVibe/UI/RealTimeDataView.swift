// DynaVibe/UI/RealTimeDataView.swift
import SwiftUI

// Assume necessary types (Axis, IdentifiableGraphPoint, etc.) are defined elsewhere or use stubs for now.

struct RealTimeDataView: View {
    @StateObject private var vm = AccelerationViewModel()
    @State private var currentDisplayMode: GraphDisplayMode = .time

    enum GraphDisplayMode: String, CaseIterable, Identifiable {
        case time = "Time Series"; case frequency = "Frequency Spectrum"; var id: String { rawValue }
    }
    private let axisColors: [Axis: Color] = [.x: .red, .y: .green, .z: .blue]

    private var currentGraphRanges: MultiLineGraphView.AxisRanges {
        if currentDisplayMode == .time {
            return vm.axisRanges
        } else {
            let firstFreq = vm.fftFrequencies.first ?? 0
            let relevantRate = vm.calculatedActualAverageSamplingRateForFFT ?? (Double(vm.actualCoreMotionRequestRate) / 2.0)
            let lastFreqPossible = relevantRate / 2.0
            let actualLastFreq = vm.fftFrequencies.last ?? lastFreqPossible
            let nyquist = max(firstFreq, actualLastFreq, 0.1)
            var maxMagnitudeOverall: Double = 0.00000001
            if let xMags = vm.fftMagnitudes[Axis.x], !xMags.isEmpty { maxMagnitudeOverall = max(maxMagnitudeOverall, xMags.max() ?? 0) }
            if let yMags = vm.fftMagnitudes[Axis.y], !yMags.isEmpty { maxMagnitudeOverall = max(maxMagnitudeOverall, yMags.max() ?? 0) }
            if let zMags = vm.fftMagnitudes[Axis.z], !zMags.isEmpty { maxMagnitudeOverall = max(maxMagnitudeOverall, zMags.max() ?? 0) }
            if maxMagnitudeOverall <= 0.00000001 { maxMagnitudeOverall = 1.0 }
            return MultiLineGraphView.AxisRanges(minY: 0, maxY: maxMagnitudeOverall, minX: 0, maxX: nyquist)
        }
    }

    private var graphPlotData: [IdentifiableGraphPoint] {
        var points: [IdentifiableGraphPoint] = []
        let sortedActiveAxes = vm.activeAxes.sorted(by: { $0.hashValue < $1.hashValue })
        if currentDisplayMode == .time {
            for axisValue in sortedActiveAxes {
                if let dataForAxis = vm.timeSeriesData[axisValue] {
                    for dataPoint in dataForAxis {
                        let currentAxis: Axis = axisValue
                        let currentXValue: Double = dataPoint.timestamp
                        let currentYValue: Double = dataPoint.value
                        points.append(IdentifiableGraphPoint(axis: currentAxis, xValue: currentXValue, yValue: currentYValue))
                    }
                }
            }
        } else {
            for axisValue in sortedActiveAxes {
                if let magnitudesForAxis = vm.fftMagnitudes[axisValue], vm.fftFrequencies.count == magnitudesForAxis.count {
                    for (index, freq) in vm.fftFrequencies.enumerated() {
                        guard index < magnitudesForAxis.count else { break }
                        let currentFftAxis: Axis = axisValue
                        let currentFftXValue: Double = freq
                        let currentFftYValue: Double = magnitudesForAxis[index]
                        points.append(IdentifiableGraphPoint(axis: currentFftAxis, xValue: currentFftXValue, yValue: currentFftYValue))
                    }
                }
            }
        }
        return points
    }

    // Helper for formatting metric values
    private func formattedMetric(_ value: Double?, unit: String = "g", precision: Int = 3) -> String { // Changed default unit to "g"
        guard let value = value else { return "N/A" }
        return String(format: "%.\(precision)f \(unit)", value)
    }

    // Helper for formatting frequency values
    private func formattedFrequency(_ value: Double?) -> String {
        guard let value = value, value > 0 else { return "N/A" } // Also check if value > 0 for frequency
        return String(format: "%.1f Hz", value)
    }

    var body: some View {
        NavigationView {
            VStack(spacing:0) {
                GlobalLiveSummaryCard(latestX: vm.latestX, latestY: vm.latestY, latestZ: vm.latestZ)
                    .padding(.horizontal).padding(.top, 8)

                Picker("Graph Mode", selection: $currentDisplayMode) {
                    ForEach(GraphDisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(SegmentedPickerStyle()).padding(.horizontal).padding(.vertical, 8)

                HStack {
                    HStack(spacing: 4) {
                        Text("Axes:").font(.caption).padding(.trailing, -4)
                        ForEach(Axis.allCases, id: \.self) { axis in
                            Button(action: { vm.toggleAxisVisibility(axis) }) {
                                Text(axis.rawValue.uppercased())
                                    .font(.system(size: 12, weight: vm.activeAxes.contains(axis) ? .bold : .regular))
                                    .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                                    .foregroundColor(vm.activeAxes.contains(axis) ? .white : (axisColors[axis] ?? .gray))
                                    .background(vm.activeAxes.contains(axis) ? (axisColors[axis] ?? .gray) : Color.clear)
                                    .cornerRadius(5).overlay(RoundedRectangle(cornerRadius: 5).stroke(axisColors[axis] ?? .gray, lineWidth: 1))
                            }
                        }
                    }
                    Spacer()
                    if vm.useLinearAccelerationSetting {
                        BubbleLevelView(roll: vm.currentRoll, pitch: vm.currentPitch).frame(width: 28, height: 28)
                    }
                }.padding(.horizontal).frame(height: 38).padding(.bottom, 4)

                HStack {
                    if vm.measurementState == .preRecordingCountdown {
                        let statusWithCountdown = "\(vm.currentStatusText) \(String(format: "%.1fs", vm.timeLeft))"
                        Text(statusWithCountdown)
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text(vm.currentStatusText)
                            .font(.caption)
                            .foregroundColor(Color(UIColor.systemGray))
                    }

                    Spacer()

                    if vm.measurementState == .recording && !(vm.autoStopRecordingEnabled && vm.measurementDurationSetting > 0) {
                        let elapsedTimeFormatted = String(format: "Rec: %.1fs", vm.elapsedTime)
                        Text(elapsedTimeFormatted).font(.caption.monospacedDigit()).foregroundColor(Color(UIColor.systemGray))
                    } else if vm.measurementState == .completed {
                        let elapsedTimeFormatted = String(format: "Total: %.2fs", vm.elapsedTime)
                        Text(elapsedTimeFormatted).font(.caption.monospacedDigit()).foregroundColor(Color(UIColor.systemGray))
                    }

                    if vm.measurementState == .recording || vm.measurementState == .completed {
                        if vm.collectedSamplesCount > 0 {
                             Text("(\(vm.collectedSamplesCount) samples)").font(.caption2).foregroundColor(Color(UIColor.systemGray2))
                        }
                    }
                }.padding(.horizontal).padding(.bottom, 8)

                MultiLineGraphView(plotData: graphPlotData, ranges: currentGraphRanges, isFrequencyDomain: currentDisplayMode == .frequency, axisColors: axisColors)
                    .frame(minHeight: 200, idealHeight: 250, maxHeight: .infinity).padding(.horizontal)
                    .background(Color(UIColor.systemGray6)).cornerRadius(10).padding(.bottom, 8)

                // === START OF MODIFIED POST-MEASUREMENT SUMMARY SECTION ===
                if vm.measurementState == .completed && vm.collectedSamplesCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Results Summary:").font(.headline).padding(.bottom, 2)

                        HStack {
                            Text("X:").font(.caption.bold()).frame(width: 25, alignment: .leading)
                            Text("Min: \(formattedMetric(vm.minX, unit:"g"))")
                            Spacer()
                            Text("Max: \(formattedMetric(vm.maxX, unit:"g"))")
                            Spacer()
                            Text("RMS: \(formattedMetric(vm.rmsX, unit:"g"))")
                            Spacer()
                            Text("Peak: \(formattedFrequency(vm.peakFrequencyX))")
                        }.font(.caption)

                        Divider()

                        HStack {
                            Text("Y:").font(.caption.bold()).frame(width: 25, alignment: .leading)
                            Text("Min: \(formattedMetric(vm.minY, unit:"g"))")
                            Spacer()
                            Text("Max: \(formattedMetric(vm.maxY, unit:"g"))")
                            Spacer()
                            Text("RMS: \(formattedMetric(vm.rmsY, unit:"g"))")
                            Spacer()
                            Text("Peak: \(formattedFrequency(vm.peakFrequencyY))")
                        }.font(.caption)

                        Divider()

                        HStack {
                            Text("Z:").font(.caption.bold()).frame(width: 25, alignment: .leading)
                            Text("Min: \(formattedMetric(vm.minZ, unit:"g"))")
                            Spacer()
                            Text("Max: \(formattedMetric(vm.maxZ, unit:"g"))")
                            Spacer()
                            Text("RMS: \(formattedMetric(vm.rmsZ, unit:"g"))")
                            Spacer()
                            Text("Peak: \(formattedFrequency(vm.peakFrequencyZ))")
                        }.font(.caption)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(height: 140) // Adjusted height for the new layout
                } else {
                    // Keep a placeholder to maintain layout consistency if no results
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 140) // Match the expected height of the summary
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                // === END OF MODIFIED POST-MEASUREMENT SUMMARY SECTION ===
                
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            if vm.isRecording || vm.measurementState == .preRecordingCountdown {
                                await vm.stopMeasurement()
                            } else {
                                await vm.startMeasurement()
                            }
                        }
                    }) {
                        Label(vm.isRecording || vm.measurementState == .preRecordingCountdown ? "Stop" : "Start",
                              systemImage: vm.isRecording || vm.measurementState == .preRecordingCountdown ? "stop.fill" : "play.fill")
                    }
                    .modifier(ControlButtonModifier(backgroundColor: vm.isRecording || vm.measurementState == .preRecordingCountdown ? .red : .green))

                    Button(action: {
                        Task { await vm.resetMeasurement() }
                    }) {
                        Label("Reset", systemImage: "arrow.clockwise")
                    }
                    .modifier(ControlButtonModifier(backgroundColor: .orange))
                    .disabled(vm.isRecording || vm.measurementState == .preRecordingCountdown)
                }
                .padding([.horizontal, .bottom])
                .padding(.top, 8)

            }
            .navigationTitle("Real-Time Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        vm.exportCSV()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(vm.isRecording || vm.measurementState == .preRecordingCountdown || vm.collectedSamplesCount == 0)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: currentDisplayMode) { oldValue, newValue in
            if newValue == .frequency && vm.isFFTReady == false && vm.collectedSamplesCount > 0 {
                Task { await vm.computeFFT() }
            }
        }
        .onAppear {
            Task { await vm.startLiveAttitudeMonitoring() }
        }
        .onDisappear {
            Task { await vm.stopLiveAttitudeMonitoring() }
        }
    }
}

struct ControlButtonModifier: ViewModifier {
    let backgroundColor: Color

    func body(content: Content) -> some View {
        content
            .fontWeight(.medium)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .shadow(radius: 3)
    }
}

struct RealTimeDataView_Previews: PreviewProvider {
    static var previews: some View {
        RealTimeDataView()
    }
}

// Dummy definitions for assumed types - these would be in separate files in the actual project
public enum Axis: String, CaseIterable, Identifiable { case x,y,z; public var id: String { rawValue }}
public struct IdentifiableGraphPoint: Identifiable { public var id = UUID(); var axis: Axis; var xValue: Double; var yValue: Double }
public struct MultiLineGraphView: View {
   public var plotData: [IdentifiableGraphPoint]
   public var ranges: MultiLineGraphView.AxisRanges
   public var isFrequencyDomain: Bool
   public var axisColors: [Axis : Color]
   public init(plotData: [IdentifiableGraphPoint], ranges: MultiLineGraphView.AxisRanges, isFrequencyDomain: Bool, axisColors: [Axis : Color]) {
       self.plotData = plotData; self.ranges = ranges; self.isFrequencyDomain = isFrequencyDomain; self.axisColors = axisColors
   }
   public var body: some View { Text("Graph Placeholder").frame(height:200) }
   public struct AxisRanges { var minY: Double = 0; var maxY: Double = 1; var minX: Double = 0; var maxX: Double = 1 }
}
public struct BubbleLevelView: View {
   public var roll: Double; public var pitch: Double
   public init(roll: Double, pitch: Double) { self.roll = roll; self.pitch = pitch}
   public var body: some View { Text("Bubble").font(.caption) }
}
public struct GlobalLiveSummaryCard: View {
   public var latestX: Double; public var latestY: Double; public var latestZ: Double
   public init(latestX: Double, latestY: Double, latestZ: Double) {self.latestX=latestX; self.latestY=latestY; self.latestZ=latestZ}
   public var body: some View { Text("Global Summary: X\(latestX, specifier: "%.2f") Y\(latestY, specifier: "%.2f") Z\(latestZ, specifier: "%.2f")").font(.caption) }
}
public struct AxisMetricCard: View { // Not used in this version of RealTimeDataView's summary
   public var title: String; public var value: Double?; public var unit: String; public var peakFrequency: Double?
   public init(title: String, value: Double?, unit: String, peakFrequency: Double?) {self.title=title; self.value=value; self.unit=unit; self.peakFrequency=peakFrequency}
   public var body: some View { Text("\(title): \(value ?? 0, specifier: "%.2f") \(unit)").font(.caption) }
}


public class AccelerationViewModel: ObservableObject {
   @Published public var latestX: Double = 0.123; @Published public var latestY: Double = 0.456; @Published public var latestZ: Double = 0.789
   @Published public var timeSeriesData: [Axis: [DataPoint]] = [.x: [DataPoint(timestamp:0, value:0)], .y: [], .z: []]
   @Published public var fftFrequencies: [Double] = [10,20,30]; @Published public var fftMagnitudes: [Axis: [Double]] = [.x:[0.1,0.2,0.3], .y:[0.1,0.2,0.3], .z:[0.1,0.2,0.3]]
   @Published public var rmsX: Double? = 0.11; @Published public var rmsY: Double? = 0.22; @Published public var rmsZ: Double? = 0.33
   @Published public var minX: Double? = -0.5; @Published public var maxX: Double? = 0.5
   @Published public var minY: Double? = -0.6; @Published public var maxY: Double? = 0.6
   @Published public var minZ: Double? = -0.7; @Published public var maxZ: Double? = 0.7
   @Published public var peakFrequencyX: Double? = 25.0
   @Published public var peakFrequencyY: Double? = nil
   @Published public var peakFrequencyZ: Double? = 28.0

   @Published public var isRecording = false
   @Published public var isFFTReady = true
   @Published public var timeLeft: Double = 3.0
   @Published public var elapsedTime: Double = 0.0
   @Published public var axisRanges: MultiLineGraphView.AxisRanges = .init(minY: -1, maxY: 1, minX: 0, maxX: 10)
   public enum MeasurementState { case idle, preRecordingCountdown, recording, completed }
   @Published public private(set) var measurementState: MeasurementState = .completed // Set to completed for preview of summary
   @Published public var activeAxes: Set<Axis> = [.x, .y, .z]
   @Published public var currentRoll: Double = 5.0
   @Published public var currentPitch: Double = -2.5
   @AppStorage("useLinearAccelerationSetting") public var useLinearAccelerationSetting: Bool = true

   public var actualCoreMotionRequestRate: Int = 128
   public var currentStatusText: String {
       switch measurementState {
       case .idle: return "Idle"
       case .preRecordingCountdown: return "Starting in..."
       case .recording: return autoStopRecordingEnabled && measurementDurationSetting > 0 ? "Recording..." : "Recording (Manual Continuous)"
       case .completed: return "Analysis Completed" // Changed for preview
       }
   }
   public var calculatedActualAverageSamplingRateForFFT: Double? = 128.0
   public var collectedSamplesCount: Int = 1024
   public var autoStopRecordingEnabled: Bool = true
   public var measurementDurationSetting: Double = 10.0


   public init() {}

    @MainActor public func startMeasurement() async { print("VM: Start Measurement Called"); measurementState = .recording; isRecording = true; }
    @MainActor public func stopMeasurement() async { print("VM: Stop Measurement Called"); measurementState = .completed; isRecording = false; }
    @MainActor public func resetMeasurement() async { print("VM: Reset Measurement Called"); measurementState = .idle; isRecording = false; timeLeft = 0.0; elapsedTime = 0.0; collectedSamplesCount = 0 }
    public func exportCSV() { print("VM: Export CSV Called") }
    @MainActor public func toggleAxisVisibility(_ axis: Axis) { print("VM: Toggle Axis \(axis) Called") }
    @MainActor public func computeFFT() async { print("VM: Compute FFT Called") }
    @MainActor public func startLiveAttitudeMonitoring() async { print("VM: Start Live Attitude Called") }
    @MainActor public func stopLiveAttitudeMonitoring() async { print("VM: Stop Live Attitude Called") }
}

public struct DataPoint { public var timestamp: Double; public var value: Double }
```
