// ViewModels/AccelerationViewModel.swift
import Foundation
import SwiftUI
import Combine
import CoreMotion

@MainActor
final class AccelerationViewModel: ObservableObject {

    // MARK: - Published State
    @Published var latestX: Double = 0.0
    @Published var latestY: Double = 0.0
    @Published var latestZ: Double = 0.0
    
    @Published var timeSeriesData: [Axis: [DataPoint]] = [.x: [], .y: [], .z: []]
    @Published var fftFrequencies: [Double] = []
    @Published var fftMagnitudes: [Axis: [Double]] = [:]
    
    @Published var rmsX: Double? = nil
    @Published var rmsY: Double? = nil
    @Published var rmsZ: Double? = nil

    @Published var isFFTReady = false
    @Published var timeLeft: Double = 0.0
    @Published var elapsedTime: Double = 0.0
    
    @Published var axisRanges: MultiLineGraphView.AxisRanges = .init(minY: -1, maxY: 1, minX: 0, maxX: 10.0)
    
    enum MeasurementState { case idle, preRecordingCountdown, recording, completed }
    @Published private(set) var measurementState: MeasurementState = .idle
    
    @Published var activeAxes: Set<Axis> = [.x, .y, .z]
    
    @Published var currentRoll: Double = 0.0
    @Published var currentPitch: Double = 0.0

    // MARK: - Display-Ready Computed Properties
    @AppStorage("accelerationUnitSetting") private var currentUnit: AccelerationUnit = .metersPerSecondSquared
    var currentUnitString: String { currentUnit.rawValue }

    // [FIX] New computed properties to prepare display strings, solving both compiler errors.
    var displayStatusText: String {
        switch measurementState {
        case .idle:
            return "Ready to start measurement."
        case .preRecordingCountdown:
            return "Starting in... \(String(format: "%.1fs", timeLeft))"
        case .recording where autoStopRecordingEnabled:
            return "Recording... time left: \(String(format: "%.1fs", timeLeft))"
        case .recording:
            return "Recording..."
        case .completed:
            return "Measurement complete."
        }
    }
    
    var displayInfoText: String {
        if measurementState == .recording || measurementState == .completed {
            if collectedSamplesCount > 0 {
                return "(\(collectedSamplesCount) samples @ \(String(format: "%.1f", elapsedTime))s)"
            }
        }
        return "" // Return empty string if no info to show
    }

    func convertValueToCurrentUnit(_ value: Double) -> Double {
        if currentUnit == .gForce { return value / 9.80665 }
        return value
    }
    
    var displayLatestX: Double { convertValueToCurrentUnit(latestX) }
    var displayLatestY: Double { convertValueToCurrentUnit(latestY) }
    var displayLatestZ: Double { convertValueToCurrentUnit(latestZ) }
    
    var displayMinX: Double? { minX.map { convertValueToCurrentUnit($0) } }
    var displayMaxX: Double? { maxX.map { convertValueToCurrentUnit($0) } }
    var displayMinY: Double? { minY.map { convertValueToCurrentUnit($0) } }
    var displayMaxY: Double? { maxY.map { convertValueToCurrentUnit($0) } }
    var displayMinZ: Double? { minZ.map { convertValueToCurrentUnit($0) } }
    var displayMaxZ: Double? { maxZ.map { convertValueToCurrentUnit($0) } }
    
    var displayRmsX: Double? { rmsX.map { convertValueToCurrentUnit($0) } }
    var displayRmsY: Double? { rmsY.map { convertValueToCurrentUnit($0) } }
    var displayRmsZ: Double? { rmsZ.map { convertValueToCurrentUnit($0) } }

    var nyquistFrequency: Double {
        let effectiveRate = calculatedActualAverageSamplingRateForFFT ?? Double(samplingRateSetting == 0 ? 100 : samplingRateSetting)
        return effectiveRate / 2.0
    }
    
    // MARK: - Settings
    @AppStorage("samplingRateSettingStorage") private var samplingRateSetting: Int = 128
    @AppStorage("measurementDurationSetting") private var measurementDuration: Double = 10.0
    @AppStorage("recordingStartDelaySetting") private var recordingStartDelay: Double = 3.0
    @AppStorage("autoStopRecordingEnabled") private var autoStopRecordingEnabled: Bool = true
    @AppStorage("useLinearAccelerationSetting") var useLinearAcceleration: Bool = false
    
    // MARK: - Private Properties
    private let recorder = AccelerationRecorder()
    private let fftAnalyzer = FFTAnalysis()
    private var dataFetchTimer: Timer?
    private var countdownTimer: Timer?
    private var recordingStartTime: Date?
    private var calculatedActualAverageSamplingRateForFFT: Double?

    // MARK: - Computed Properties
    var isRecording: Bool {
        return measurementState == .recording || measurementState == .preRecordingCountdown
    }
    
    private var collectedSamplesCount: Int { timeSeriesData[.x]?.count ?? 0 }
    private var minX: Double? { timeSeriesData[.x]?.min(by: { $0.value < $1.value })?.value }
    private var maxX: Double? { timeSeriesData[.x]?.max(by: { $0.value < $1.value })?.value }
    private var minY: Double? { timeSeriesData[.y]?.min(by: { $0.value < $1.value })?.value }
    private var maxY: Double? { timeSeriesData[.y]?.max(by: { $0.value < $1.value })?.value }
    private var minZ: Double? { timeSeriesData[.z]?.min(by: { $0.value < $1.value })?.value }
    private var maxZ: Double? { timeSeriesData[.z]?.max(by: { $0.value < $1.value })?.value }
    
    var peakFrequencyX: Double? { findPeakFrequency(for: .x) }
    var peakFrequencyY: Double? { findPeakFrequency(for: .y) }
    var peakFrequencyZ: Double? { findPeakFrequency(for: .z) }
    
    init() {
        recorder.attitudeUpdateHandler = { [weak self] attitude in
            DispatchQueue.main.async {
                self?.currentRoll = attitude.roll * 180.0 / .pi
                self?.currentPitch = attitude.pitch * 180.0 / .pi
            }
        }
    }

    func startMeasurement() async {
        guard measurementState == .idle else { return }
        resetDataForNewRecording()
        if useLinearAcceleration { startLiveAttitudeMonitoring() }
        
        if recordingStartDelay > 0 {
            measurementState = .preRecordingCountdown
            timeLeft = recordingStartDelay
            startCountdownTimer(duration: recordingStartDelay) { self.beginActualRecording() }
        } else {
            beginActualRecording()
        }
    }

    func stopMeasurement() async {
        countdownTimer?.invalidate()
        dataFetchTimer?.invalidate()
        
        if recorder.isCurrentlyRecordingData {
            recorder.stopRecording()
            captureNewSamples()
        }
        
        let wasRecording = (measurementState == .recording)
        measurementState = .completed
        
        if wasRecording && collectedSamplesCount > 0 {
            calculateFinalMetrics()
            await computeFFT()
        } else {
            await resetMeasurement()
        }
    }

    func resetMeasurement() async {
        if isRecording { await stopMeasurement() }
        resetDataForNewRecording()
        measurementState = .idle
        timeLeft = recordingStartDelay
        elapsedTime = 0
        updateGraphRangesForIdle()
    }

    func computeFFT() async {
        guard collectedSamplesCount > 1, let rateForFFT = calculatedActualAverageSamplingRateForFFT else {
            isFFTReady = false
            return
        }
        
        isFFTReady = false
        let xValues = (timeSeriesData[.x] ?? []).map { $0.value }
        let yValues = (timeSeriesData[.y] ?? []).map { $0.value }
        let zValues = (timeSeriesData[.z] ?? []).map { $0.value }

        let (xMag, yMag, zMag, freqs) = await Task.detached(priority: .userInitiated) { [analyzer = self.fftAnalyzer] in
            let resultsX = analyzer.performFFT(input: xValues, samplingRate: rateForFFT)
            let resultsY = analyzer.performFFT(input: yValues, samplingRate: rateForFFT)
            let resultsZ = analyzer.performFFT(input: zValues, samplingRate: rateForFFT)
            return (resultsX.magnitude, resultsY.magnitude, resultsZ.magnitude, resultsX.frequencies)
        }.value

        fftMagnitudes[.x] = xMag
        fftMagnitudes[.y] = yMag
        fftMagnitudes[.z] = zMag
        fftFrequencies = freqs
        isFFTReady = true
    }
    
    func exportCSV() {
        guard let dataX = timeSeriesData[.x], let dataY = timeSeriesData[.y], let dataZ = timeSeriesData[.z], !dataX.isEmpty else { return }
        let combinedData = zip(dataX, zip(dataY, dataZ)).map { ($0.0.timestamp, $0.0.value, $0.1.0.value, $0.1.1.value) }

        if let url = CSVExporter.exportAccelerationData(combinedData) {
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            let keyWindow = UIApplication.shared.connectedScenes.filter({$0.activationState == .foregroundActive}).compactMap({$0 as? UIWindowScene}).first?.windows.filter({$0.isKeyWindow}).first
            keyWindow?.rootViewController?.present(activityVC, animated: true, completion: nil)
        }
    }
    
    func toggleAxisVisibility(_ axis: Axis) {
        if activeAxes.contains(axis) { activeAxes.remove(axis) } else { activeAxes.insert(axis) }
    }
    
    func startLiveAttitudeMonitoring() { recorder.startLiveAttitudeUpdates() }
    func stopLiveAttitudeMonitoring() { recorder.stopLiveAttitudeUpdates() }

    private func beginActualRecording() {
        measurementState = .recording
        recordingStartTime = Date()
        
        recorder.useDeviceMotionForData = self.useLinearAcceleration
        recorder.motionSessionPublic.samplingRate = self.samplingRateSetting == 0 ? 100 : self.samplingRateSetting
        
        recorder.startRecording()
        startDataFetchTimer()
        
        if autoStopRecordingEnabled && measurementDuration > 0 {
            timeLeft = measurementDuration
            startCountdownTimer(duration: measurementDuration) { [weak self] in Task { await self?.stopMeasurement() } }
        }
    }

    private func startDataFetchTimer() {
        let interval = 1.0 / 30.0
        dataFetchTimer?.invalidate()
        dataFetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.captureNewSamples()
            self?.updateElapsedTime()
        }
    }

    private func startCountdownTimer(duration: TimeInterval, completion: @escaping () -> Void) {
        let timerStartTime = Date()
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            let elapsed = Date().timeIntervalSince(timerStartTime)
            self?.timeLeft = max(0, duration - elapsed)
            if elapsed >= duration {
                timer.invalidate()
                completion()
            }
        }
    }
    
    private func captureNewSamples() {
        let allRecordedData = recorder.getRecordedData()
        guard !allRecordedData.isEmpty else { return }

        var newX: [DataPoint] = []; var newY: [DataPoint] = []; var newZ: [DataPoint] = []
        newX.reserveCapacity(allRecordedData.count); newY.reserveCapacity(allRecordedData.count); newZ.reserveCapacity(allRecordedData.count)

        for sample in allRecordedData {
            newX.append(DataPoint(timestamp: sample.timestamp, value: sample.x))
            newY.append(DataPoint(timestamp: sample.timestamp, value: sample.y))
            // [FIX] Corrected typo from `aple.z` to `sample.z`
            newZ.append(DataPoint(timestamp: sample.timestamp, value: sample.z))
        }

        self.timeSeriesData[.x] = newX; self.timeSeriesData[.y] = newY; self.timeSeriesData[.z] = newZ
        
        if let lastSample = allRecordedData.last {
            latestX = lastSample.x; latestY = lastSample.y; latestZ = lastSample.z
            
            if measurementState == .recording && !autoStopRecordingEnabled {
                let windowDuration = 10.0
                axisRanges.maxX = lastSample.timestamp
                axisRanges.minX = max(0, lastSample.timestamp - windowDuration)
            }
        }
    }

    private func updateElapsedTime() {
        guard let startTime = recordingStartTime, measurementState == .recording else { return }
        elapsedTime = Date().timeIntervalSince(startTime)
    }

    private func resetDataForNewRecording() {
        timeSeriesData = [.x: [], .y: [], .z: []]; fftMagnitudes = [:]; fftFrequencies = []
        isFFTReady = false; rmsX = nil; rmsY = nil; rmsZ = nil
        latestX = 0; latestY = 0; latestZ = 0; currentRoll = 0; currentPitch = 0
        calculatedActualAverageSamplingRateForFFT = nil
        recorder.clear()
    }
    
    private func updateGraphRangesForIdle() {
        axisRanges.minX = 0
        axisRanges.maxX = autoStopRecordingEnabled ? measurementDuration : 10.0
        axisRanges.minY = -1.0; axisRanges.maxY = 1.0
    }

    private func calculateFinalMetrics() {
        guard collectedSamplesCount > 1, let dataX = timeSeriesData[.x], let firstTimestamp = dataX.first?.timestamp, let lastTimestamp = dataX.last?.timestamp else { return }
        
        let duration = lastTimestamp - firstTimestamp
        if duration > 0 { calculatedActualAverageSamplingRateForFFT = Double(dataX.count - 1) / duration }
        else { calculatedActualAverageSamplingRateForFFT = Double(samplingRateSetting) }
        
        rmsX = calculateOverallRMS(for: .x); rmsY = calculateOverallRMS(for: .y); rmsZ = calculateOverallRMS(for: .z)
        
        axisRanges.minX = firstTimestamp; axisRanges.maxX = lastTimestamp
    }

    private func calculateOverallRMS(for axis: Axis) -> Double? {
        guard let dataPoints = timeSeriesData[axis], !dataPoints.isEmpty else { return nil }
        let sumOfSquares = dataPoints.reduce(0.0) { $0 + ($1.value * $1.value) }
        return sqrt(sumOfSquares / Double(dataPoints.count))
    }

    private func findPeakFrequency(for axis: Axis) -> Double? {
        guard let magnitudes = fftMagnitudes[axis], !magnitudes.isEmpty, let frequencies = Optional(self.fftFrequencies), !frequencies.isEmpty, magnitudes.count == frequencies.count else { return nil }
        return zip(frequencies, magnitudes).max { $0.1 < $1.1 }?.0
    }

    // MARK: - Dynamic Axis Range and Tick Calculation
    
    /// Returns the min and max for the X axis (time or frequency) based on the current data and mode.
    func dynamicXAxisRange(isFrequencyDomain: Bool) -> (min: Double, max: Double)? {
        if isFrequencyDomain {
            guard !fftFrequencies.isEmpty else { return nil }
            let minF = fftFrequencies.min() ?? 0
            let maxF = fftFrequencies.max() ?? 1
            return (minF, maxF)
        } else {
            // For time domain, use 0 to the latest timestamp (or measurementDuration if completed)
            let allTimestamps = timeSeriesData.values.flatMap { $0.map { $0.timestamp } }
            if measurementState == .completed {
                return (0, measurementDuration)
            } else if let maxT = allTimestamps.max(), maxT > 0 {
                return (0, maxT)
            } else {
                return (0, 1)
            }
        }
    }

    /// Returns the min and max for the Y axis (amplitude/magnitude) based on the current data and mode.
    func dynamicYAxisRange(isFrequencyDomain: Bool) -> (min: Double, max: Double)? {
        if isFrequencyDomain {
            let allMagnitudes = fftMagnitudes.values.flatMap { $0 }
            guard !allMagnitudes.isEmpty else { return nil }
            let minY = allMagnitudes.min() ?? 0
            let maxY = allMagnitudes.max() ?? 1
            return (minY, maxY)
        } else {
            let allValues = timeSeriesData.values.flatMap { $0.map { $0.value } }
            guard !allValues.isEmpty else { return nil }
            let minY = allValues.min() ?? 0
            let maxY = allValues.max() ?? 1
            return (minY, maxY)
        }
    }

    /// Returns a 'nice' axis range and tick interval for the given min/max and desired tick count.
    func niceAxisRangeAndTicks(min: Double, max: Double, maxTicks: Int = 5) -> (niceMin: Double, niceMax: Double, tickSpacing: Double, ticks: [Double]) {
        guard min != max else {
            // Avoid zero range
            let delta = abs(min == 0 ? 1 : min * 0.1)
            return (min - delta, max + delta, delta, [min - delta, min, max + delta])
        }
        let range = niceNum(max - min, round: false)
        let tickSpacing = niceNum(range / Double(maxTicks - 1), round: true)
        let niceMin = floor(min / tickSpacing) * tickSpacing
        let niceMax = ceil(max / tickSpacing) * tickSpacing
        var ticks: [Double] = []
        var tick = niceMin
        while tick <= niceMax + 0.5 * tickSpacing {
            ticks.append(tick)
            tick += tickSpacing
        }
        return (niceMin, niceMax, tickSpacing, ticks)
    }

    /// Helper for 'nice' numbers (for axis ticks)
    private func niceNum(_ range: Double, round: Bool) -> Double {
        let exponent = floor(log10(range))
        let fraction = range / pow(10, exponent)
        let niceFraction: Double
        if round {
            if fraction < 1.5 { niceFraction = 1 }
            else if fraction < 3 { niceFraction = 2 }
            else if fraction < 7 { niceFraction = 5 }
            else { niceFraction = 10 }
        } else {
            if fraction <= 1 { niceFraction = 1 }
            else if fraction <= 2 { niceFraction = 2 }
            else if fraction <= 5 { niceFraction = 5 }
            else { niceFraction = 10 }
        }
        return niceFraction * pow(10, exponent)
    }

    /// Call this to update axisRanges for the current data and mode (time/frequency)
    func updateAxisRanges(isFrequencyDomain: Bool) {
        if let (minX, maxX) = dynamicXAxisRange(isFrequencyDomain: isFrequencyDomain),
           let (minY, maxY) = dynamicYAxisRange(isFrequencyDomain: isFrequencyDomain) {
            let xAxis = niceAxisRangeAndTicks(min: minX, max: maxX)
            let yAxis = niceAxisRangeAndTicks(min: minY, max: maxY)
            axisRanges.minX = xAxis.niceMin
            axisRanges.maxX = xAxis.niceMax
            axisRanges.minY = yAxis.niceMin
            axisRanges.maxY = yAxis.niceMax
            // Optionally: store ticks for use in the graph view
        }
    }
}
