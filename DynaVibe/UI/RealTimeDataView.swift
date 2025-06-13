// UI/RealTimeDataView.swift
import SwiftUI

// [FIX] The erroneous, duplicate definition of MultiLineGraphView has been completely removed from this file.
// This view now correctly uses the single, authoritative definition from MultiLineGraphView.swift.

struct RealTimeDataView: View {
    @Binding var project: Project
    @StateObject private var vm = AccelerationViewModel()
    @State private var currentDisplayMode: GraphDisplayMode = .time
    @State private var hasSavedMeasurement = false

    enum GraphDisplayMode: String, CaseIterable, Identifiable {
        case time = "Time Series"
        case frequency = "Frequency Spectrum"
        var id: String { rawValue }
    }
    private let axisColors: [Axis: Color] = [.x: .red, .y: .green, .z: .blue]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HeaderControlView(vm: vm, currentDisplayMode: $currentDisplayMode)
                    .padding(.horizontal)
                    .padding(.top, 8)

                StatusInfoView(vm: vm)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                MultiLineGraphView(
                    plotData: graphPlotData,
                    ranges: currentGraphRanges,
                    isFrequencyDomain: currentDisplayMode == .frequency,
                    axisColors: axisColors,
                    yAxisLabelUnit: vm.currentUnitString,
                    xTicks: xTicks,
                    yTicks: yTicks,
                    xGridLines: xGridLines,
                    yGridLines: yGridLines,
                    isLoading: $vm.isComputingFFT
                )
                .frame(minHeight: 200, idealHeight: 250, maxHeight: .infinity)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if vm.measurementState == .completed && (vm.timeSeriesData[.x]?.count ?? 0) > 0 {
                    ResultsSummaryView(vm: vm)
                } else {
                    Color.clear
                        .frame(height: 140)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                
                ActionButtonsView(vm: vm)
                    .padding([.horizontal, .bottom])
                    .padding(.top, 8)
            }
            .navigationTitle("Real-Time Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: vm.exportCSV) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(vm.isRecording || (vm.timeSeriesData[.x]?.isEmpty ?? true))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: currentDisplayMode) { _, newValue in
            vm.updateAxisRanges(isFrequencyDomain: newValue == .frequency)
            if newValue == .frequency && !vm.isFFTReady && (vm.timeSeriesData[.x]?.count ?? 0) > 0 {
                Task { await vm.computeFFT() }
            }
        }
        .onAppear {
            Task { vm.startLiveAttitudeMonitoring() }
            vm.updateAxisRanges(isFrequencyDomain: currentDisplayMode == .frequency)
        }
        .onDisappear { Task { vm.stopLiveAttitudeMonitoring() } }
        .onChange(of: vm.isFFTReady) { _, newValue in
            if newValue && vm.measurementState == .completed {
                saveMeasurementIfNeeded()
            }
        }
        .onChange(of: vm.measurementState) { _, newState in
            if newState == .recording || newState == .preRecordingCountdown || newState == .idle {
                hasSavedMeasurement = false
            }
        }
    }
    
    private var currentGraphRanges: MultiLineGraphView.AxisRanges {
        if currentDisplayMode == .time {
            let yValues = graphPlotData.filter { vm.activeAxes.contains($0.axis) }.map { $0.yValue }
            var minY = yValues.min() ?? -1.0
            var maxY = yValues.max() ?? 1.0
            if minY == maxY { minY -= 0.5; maxY += 0.5 }
            let padding = (maxY - minY) * 0.1
            return .init(minY: minY - padding, maxY: maxY + padding, minX: vm.axisRanges.minX, maxX: vm.axisRanges.maxX)
        } else {
            let magnitudes = graphPlotData.filter { vm.activeAxes.contains($0.axis) }.map { $0.yValue }
            let maxMag = magnitudes.max() ?? (vm.currentUnitString == "g" ? 0.1 : 1.0)
            return .init(minY: 0, maxY: maxMag * 1.1, minX: 0, maxX: vm.nyquistFrequency)
        }
    }

    private var graphPlotData: [IdentifiableGraphPoint] {
        let sortedActiveAxes = vm.activeAxes.sorted(by: { $0.hashValue < $1.hashValue })
        if currentDisplayMode == .time {
            return sortedActiveAxes.flatMap { axis -> [IdentifiableGraphPoint] in
                (vm.timeSeriesData[axis] ?? []).map {
                    IdentifiableGraphPoint(axis: axis, xValue: $0.timestamp, yValue: vm.convertValueToCurrentUnit($0.value))
                }
            }
        } else {
            return sortedActiveAxes.flatMap { axis -> [IdentifiableGraphPoint] in
                guard let magnitudes = vm.fftMagnitudes[axis], vm.fftFrequencies.count == magnitudes.count else { return [] }
                return zip(vm.fftFrequencies, magnitudes).map { (freq, mag) in
                    IdentifiableGraphPoint(axis: axis, xValue: freq, yValue: vm.convertValueToCurrentUnit(mag))
                }
            }
        }
    }

    // --- Tick Arrays provided by the view model ---
    private var xTicks: [Double] { vm.xAxisTicks }
    private var xGridLines: [Double] {
        if currentDisplayMode == .frequency {
            let minX = currentGraphRanges.minX
            let maxX = currentGraphRanges.maxX
            let start = ceil(minX / 1.0) * 1.0
            return stride(from: start, through: maxX, by: 1.0).map { Double(round(3*$0)/3) }
        } else {
            let minX = currentGraphRanges.minX
            let maxX = currentGraphRanges.maxX
            let start = ceil(minX / 0.2) * 0.2
            return stride(from: start, through: maxX, by: 0.2).map { Double(round(5*$0)/5) }
        }
    }
    private var yTicks: [Double] { vm.yAxisTicks }
    private var yGridLines: [Double] {
        // Same as yTicks per user request
        return yTicks
    }

    private func saveMeasurementIfNeeded() {
        guard !hasSavedMeasurement,
              vm.measurementState == .completed,
              (vm.timeSeriesData[.x]?.isEmpty == false) else { return }

        let measurement = Measurement(
            date: Date(),
            timeSeriesData: vm.timeSeriesData,
            fftFrequencies: vm.fftFrequencies,
            fftMagnitudes: vm.fftMagnitudes,
            rmsX: vm.rmsX,
            rmsY: vm.rmsY,
            rmsZ: vm.rmsZ,
            minX: vm.displayMinX,
            maxX: vm.displayMaxX,
            minY: vm.displayMinY,
            maxY: vm.displayMaxY,
            minZ: vm.displayMinZ,
            maxZ: vm.displayMaxZ,
            peakFrequencyX: vm.peakFrequencyX,
            peakFrequencyY: vm.peakFrequencyY,
            peakFrequencyZ: vm.peakFrequencyZ
        )

        project.measurements.append(measurement)
        hasSavedMeasurement = true
        Task { await vm.resetMeasurement() }
    }
}

// MARK: - Subviews
private struct HeaderControlView: View {
    @ObservedObject var vm: AccelerationViewModel
    @Binding var currentDisplayMode: RealTimeDataView.GraphDisplayMode
    private let axisColors: [Axis: Color] = [.x: .red, .y: .green, .z: .blue]

    var body: some View {
        VStack(spacing: 8) {
            GlobalLiveSummaryCard(latestX: vm.displayLatestX, latestY: vm.displayLatestY, latestZ: vm.displayLatestZ, unitString: vm.currentUnitString)
            Picker("Graph Mode", selection: $currentDisplayMode) {
                ForEach(RealTimeDataView.GraphDisplayMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
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
                if vm.useLinearAcceleration {
                    AttitudeIndicatorView(roll: vm.currentRoll, pitch: vm.currentPitch)
                }
            }.frame(height: 38)
        }
    }
}

private struct AttitudeIndicatorView: View {
    let roll: Double
    let pitch: Double
    var body: some View {
        HStack(spacing: 8) {
            BubbleLevelView(roll: roll, pitch: pitch)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "P: %+.1f°", pitch))
                Text(String(format: "R: %+.1f°", roll))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}

private struct StatusInfoView: View {
    @ObservedObject var vm: AccelerationViewModel
    var body: some View {
        HStack {
            Text(vm.displayStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(vm.displayInfoText)
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .frame(height: 15)
    }
}

private struct ResultsSummaryView: View {
    @ObservedObject var vm: AccelerationViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Results Summary (\(vm.currentUnitString))").font(.headline).padding(.bottom, 2)
            ResultRow(axis: "X", min: vm.displayMinX, max: vm.displayMaxX, rms: vm.displayRmsX, peakFreq: vm.peakFrequencyX)
            Divider()
            ResultRow(axis: "Y", min: vm.displayMinY, max: vm.displayMaxY, rms: vm.displayRmsY, peakFreq: vm.peakFrequencyY)
            Divider()
            ResultRow(axis: "Z", min: vm.displayMinZ, max: vm.displayMaxZ, rms: vm.displayRmsZ, peakFreq: vm.peakFrequencyZ)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10)
        .padding([.horizontal, .vertical], 4)
        .frame(height: 140)
    }

    private struct ResultRow: View {
        let axis: String; let min: Double?; let max: Double?; let rms: Double?; let peakFreq: Double?
        var body: some View {
            HStack {
                Text(axis + ":").font(.caption.bold()).frame(width: 25, alignment: .leading)
                Text("Min: \(formattedMetric(min))"); Spacer()
                Text("Max: \(formattedMetric(max))"); Spacer()
                Text("RMS: \(formattedMetric(rms))"); Spacer()
                Text("Peak: \(formattedFrequency(peakFreq))")
            }.font(.caption)
        }
        private func formattedMetric(_ v: Double?) -> String { v.map { String(format: "%.3f", $0) } ?? "N/A" }
        private func formattedFrequency(_ v: Double?) -> String { v.map { String(format: "%.1f Hz", $0) } ?? "N/A" }
    }
}

private struct ActionButtonsView: View {
    @ObservedObject var vm: AccelerationViewModel
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { Task { if vm.isRecording { await vm.stopMeasurement() } else { await vm.startMeasurement() } } }) {
                Label(vm.isRecording ? "Stop" : "Start", systemImage: vm.isRecording ? "stop.fill" : "play.fill")
            }.modifier(ControlButtonModifier(backgroundColor: vm.isRecording ? .red : .green))
            Button(action: { Task { await vm.resetMeasurement() } }) {
                Label("Reset", systemImage: "arrow.clockwise")
            }.modifier(ControlButtonModifier(backgroundColor: .orange)).disabled(vm.isRecording)
        }
    }
}

struct ControlButtonModifier: ViewModifier {
    let backgroundColor: Color
    func body(content: Content) -> some View {
        content.fontWeight(.medium).padding(.vertical, 10).padding(.horizontal, 20).frame(maxWidth: .infinity)
            .background(backgroundColor).foregroundColor(.white).cornerRadius(8).shadow(radius: 3)
    }
}

struct RealTimeDataView_Previews: PreviewProvider {
    static var previews: some View {
        RealTimeDataView(project: .constant(Project(name: "Preview", description: "")))
    }
}
