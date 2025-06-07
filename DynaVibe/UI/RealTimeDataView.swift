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
            // For time domain, Y-axis unit depends on the selected unit in ViewModel
            // The actual range values in vm.axisRanges are raw (m/s^2).
            // MultiLineGraphView will be responsible for displaying the correct unit string.
            return vm.axisRanges
        } else {
            // Frequency domain Y-axis is magnitude, typically unitless or specific to FFT context,
            // but if based on m/s^2 or g, it might also need adjustment if vm provides converted FFT magnitudes.
            // For now, assume FFT magnitudes are not unit-converted for display scaling yet by vm.
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
                        // Pass raw m/s² data to the graph. Graph will use displayValue for Y-axis scaling if needed,
                        // or just display the unit string. For now, assume graph takes raw, and label shows unit.
                        let currentXValue: Double = dataPoint.timestamp
                        let currentYValue: Double = dataPoint.value // Raw value
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
                        let currentFftYValue: Double = magnitudesForAxis[index] // Raw magnitude
                        points.append(IdentifiableGraphPoint(axis: currentFftAxis, xValue: currentFftXValue, yValue: currentFftYValue))
                    }
                }
            }
        }
        return points
    }

    // Helper for formatting metric values - uses vm.currentUnitString implicitly if not passed
    // For this view, we will pass vm.currentUnitString to AxisMetricCard.
    // These helpers are for the new summary table.
    private func formattedMetric(_ value: Double?, precision: Int = 3) -> String {
        guard let val = value else { return "N/A" } // Value is already converted by ViewModel's displayXXX properties
        return String(format: "%.\(precision)f", val)
    }

    private func formattedFrequency(_ value: Double?) -> String {
        guard let value = value, value > 0 else { return "N/A" }
        return String(format: "%.1f Hz", value)
    }

    var body: some View {
        NavigationView {
            VStack(spacing:0) {
                GlobalLiveSummaryCard(
                    latestX: vm.displayLatestX,
                    latestY: vm.displayLatestY,
                    latestZ: vm.displayLatestZ,
                    unitString: vm.currentUnitString
                )
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

                MultiLineGraphView(
                    plotData: graphPlotData,
                    ranges: currentGraphRanges,
                    isFrequencyDomain: currentDisplayMode == .frequency,
                    axisColors: axisColors,
                    yAxisLabelUnit: vm.currentUnitString // Pass the unit string
                )
                .frame(minHeight: 200, idealHeight: 250, maxHeight: .infinity).padding(.horizontal)
                .background(Color(UIColor.systemGray6)).cornerRadius(10).padding(.bottom, 8)

                if vm.measurementState == .completed && vm.collectedSamplesCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Results Summary:").font(.headline).padding(.bottom, 2)

                        HStack {
                            Text("X:").font(.caption.bold()).frame(width: 25, alignment: .leading)
                            Text("Min: \(formattedMetric(vm.displayMinX))")
                            Spacer()
                            Text("Max: \(formattedMetric(vm.displayMaxX))")
                            Spacer()
                            Text("RMS: \(formattedMetric(vm.displayRmsX))")
                            Spacer()
                            Text("Peak: \(formattedFrequency(vm.peakFrequencyX))")
                        }.font(.caption)

                        Divider()

                        HStack {
                            Text("Y:").font(.caption.bold()).frame(width: 25, alignment: .leading)
                            Text("Min: \(formattedMetric(vm.displayMinY))")
                            Spacer()
                            Text("Max: \(formattedMetric(vm.displayMaxY))")
                            Spacer()
                            Text("RMS: \(formattedMetric(vm.displayRmsY))")
                            Spacer()
                            Text("Peak: \(formattedFrequency(vm.peakFrequencyY))")
                        }.font(.caption)

                        Divider()

                        HStack {
                            Text("Z:").font(.caption.bold()).frame(width: 25, alignment: .leading)
                            Text("Min: \(formattedMetric(vm.displayMinZ))")
                            Spacer()
                            Text("Max: \(formattedMetric(vm.displayMaxZ))")
                            Spacer()
                            Text("RMS: \(formattedMetric(vm.displayRmsZ))")
                            Spacer()
                            Text("Peak: \(formattedFrequency(vm.peakFrequencyZ))")
                        }.font(.caption)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(height: 140)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 140)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                
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
   public var ranges: MultiLineGraphView.AxisRanges // Ensure this matches the struct within MultiLineGraphView
   public var isFrequencyDomain: Bool
   public var axisColors: [Axis : Color]
   public var yAxisLabelUnit: String // Added this
   public init(plotData: [IdentifiableGraphPoint], ranges: MultiLineGraphView.AxisRanges, isFrequencyDomain: Bool, axisColors: [Axis : Color], yAxisLabelUnit: String) { // Added to init
       self.plotData = plotData; self.ranges = ranges; self.isFrequencyDomain = isFrequencyDomain; self.axisColors = axisColors; self.yAxisLabelUnit = yAxisLabelUnit
   }
   public var body: some View { Text("Graph Placeholder (\(yAxisLabelUnit))").frame(height:200) }
   public struct AxisRanges { var minY: Double = 0; var maxY: Double = 1; var minX: Double = 0; var maxX: Double = 1 }
}
public struct BubbleLevelView: View {
   public var roll: Double; public var pitch: Double
   public init(roll: Double, pitch: Double) { self.roll = roll; self.pitch = pitch}
   public var body: some View { Text("Bubble").font(.caption) }
}
public struct GlobalLiveSummaryCard: View {
   public var latestX: Double; public var latestY: Double; public var latestZ: Double
   public var unitString: String // Added this
   public init(latestX: Double, latestY: Double, latestZ: Double, unitString: String) { // Added to init
        self.latestX=latestX; self.latestY=latestY; self.latestZ=latestZ; self.unitString = unitString
    }
   public var body: some View { Text("Global Summary: X\(latestX, specifier: "%.2f") Y\(latestY, specifier: "%.2f") Z\(latestZ, specifier: "%.2f") \(unitString)").font(.caption) }
}
public struct AxisMetricCard: View {
   public var title: String; public var value: Double?; public var unit: String; public var peakFrequency: Double?
   public init(title: String, value: Double?, unit: String, peakFrequency: Double?) {self.title=title; self.value=value; self.unit=unit; self.peakFrequency=peakFrequency}
   public var body: some View { Text("\(title): \(value ?? 0, specifier: "%.2f") \(unit) Peak: \(peakFrequency ?? 0, specifier: "%.1f")Hz").font(.caption) }
}


public class AccelerationViewModel: ObservableObject {
   @Published public var latestX: Double = 0.123; @Published public var latestY: Double = 0.456; @Published public var latestZ: Double = 0.789
   // Display computed properties
    public var displayLatestX: Double { latestX } // Simplified for stub
    public var displayLatestY: Double { latestY }
    public var displayLatestZ: Double { latestZ }
    public var displayMinX: Double? { minX }
    public var displayMaxX: Double? { maxX }
    public var displayRmsX: Double? { rmsX }
    public var displayMinY: Double? { minY }
    public var displayMaxY: Double? { maxY }
    public var displayRmsY: Double? { rmsY }
    public var displayMinZ: Double? { minZ }
    public var displayMaxZ: Double? { maxZ }
    public var displayRmsZ: Double? { rmsZ }
    @Published public var currentUnitString: String = "m/s²"


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
   @Published public private(set) var measurementState: MeasurementState = .completed
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
       case .completed: return "Analysis Completed"
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
