// ViewModels/AccelerationViewModel.swift
import Foundation
import SwiftUI
import Combine
import CoreMotion

// Ensure MultiLineGraphView (for .AxisRanges), DataPoint, Axis types are accessible
// from their respective files (e.g., UI/MultiLineGraphView.swift, Models/DataPoint.swift, Shared/AxisAndLegend.swift)

final class AccelerationViewModel: MotionSessionReceiver, ObservableObject {

    // MARK: - Published State
    @Published var latestX: Double = 0.0
    @Published var latestY: Double = 0.0
    @Published var latestZ: Double = 0.0
    @Published var timeSeriesData: [Axis: [DataPoint]] = [:]
    @Published var fftFrequencies: [Double] = []
    @Published var fftMagnitudes: [Axis: [Double]] = [:]
    @Published var rmsX: Double = 0.0
    @Published var rmsY: Double = 0.0
    @Published var rmsZ: Double = 0.0
    @Published var isRecording = false // True ONLY during actual data acquisition phase
    @Published var isFFTReady = false
    @Published var timeLeft: Double = 0.0 // Shows pre-recording delay OR recording duration countdown
    @Published var elapsedTime: Double = 0.0 // Tracks actual data recording time
    @Published var axisRanges: MultiLineGraphView.AxisRanges = .init(minY: -1, maxY: 1, minX: 0, maxX: 10)
    enum MeasurementState { case idle, preRecordingCountdown, recording, completed }
    @Published private(set) var measurementState: MeasurementState = .idle
    @Published var activeAxes: Set<Axis> = [.x, .y, .z]
    @Published var currentRoll: Double = 0.0
    @Published var currentPitch: Double = 0.0

    // MARK: - Settings
    @AppStorage("samplingRateSettingStorage") var samplingRateSettingStorage: Int = 128 {
        didSet { updateSettingsDependentState() }
    }
    @AppStorage("measurementDurationSetting") var measurementDurationSetting: Double = 10.0 {
        didSet { updateSettingsDependentState() }
    }
    @AppStorage("recordingStartDelaySetting") var recordingStartDelaySetting: Double = 3.0 {
        didSet { updateSettingsDependentState() }
    }
    @AppStorage("autoStopRecordingEnabled") var autoStopRecordingEnabled: Bool = true {
        didSet { updateSettingsDependentState() }
    }
    @AppStorage("useLinearAccelerationSetting") var useLinearAccelerationSetting: Bool = false {
        didSet { if oldValue != useLinearAccelerationSetting { toggleLiveAttitudeBasedOnSetting() } }
    }

    // MARK: - Computed Properties
    var actualCoreMotionRequestRate: Int {
        switch samplingRateSettingStorage {
        case 0: return 1000
        case 32, 64, 128: return samplingRateSettingStorage
        default: return 128
        }
    }
    var currentStatusText: String {
        switch measurementState {
        case .idle: return "Idle"
        case .preRecordingCountdown: return "Starting in..."
        case .recording: return autoStopRecordingEnabled && measurementDurationSetting > 0 ? "Recording..." : "Recording (Manual Stop)"
        case .completed: return "Completed"
        }
    }
    var currentEffectiveMaxGraphDuration: Double {
        autoStopRecordingEnabled && measurementDurationSetting > 0 ? measurementDurationSetting : 10.0
    }
    var currentInitialTimeLeft: Double {
        recordingStartDelaySetting > 0 ? recordingStartDelaySetting : (autoStopRecordingEnabled && measurementDurationSetting > 0 ? measurementDurationSetting : 0)
    }
    var collectedSamplesCount: Int { timeSeriesData[Axis.x]?.count ?? 0 }
    var minX: Double? { timeSeriesData[Axis.x]?.min(by: { $0.value < $1.value })?.value }
    var maxX: Double? { timeSeriesData[Axis.x]?.max(by: { $0.value < $1.value })?.value }
    var minY: Double? { timeSeriesData[Axis.y]?.min(by: { $0.value < $1.value })?.value }
    var maxY: Double? { timeSeriesData[Axis.y]?.max(by: { $0.value < $1.value })?.value }
    var minZ: Double? { timeSeriesData[Axis.z]?.min(by: { $0.value < $1.value })?.value }
    var maxZ: Double? { timeSeriesData[Axis.z]?.max(by: { $0.value < $1.value })?.value }
    var peakFrequencyX: Double? { findPeakFrequency(for: .x) }
    var peakFrequencyY: Double? { findPeakFrequency(for: .y) }
    var peakFrequencyZ: Double? { findPeakFrequency(for: .z) }
    var calculatedActualAverageSamplingRateForFFT: Double?

    // MARK: - Private Properties
    private let recorder: AccelerationRecorder
    private let fftAnalyzer: FFTAnalysis
    private var dataFetchTimer: Timer?; private var durationCountdownTimer: Timer?; private var preRecordingDelayTimer: Timer?
    private var lastProcessedSampleTimestamp: TimeInterval = 0
    private let motionSessionForLiveAttitude = MotionSession.current()
    private var isLiveAttitudeMonitoringActive = false
    private let liveAttitudeUpdateInterval: TimeInterval = 1.0 / 30.0
    private var recordingActualStartTime: Date?; private var preRecordingPhaseStartTime: Date?

    // MARK: - Initialization & Deinit
    override init() {
        self.recorder = AccelerationRecorder()
        self.fftAnalyzer = FFTAnalysis()
        super.init()

        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.recorder.motionSessionPublic.samplingRate = strongSelf.actualCoreMotionRequestRate
            Axis.allCases.forEach { axis in
                strongSelf.timeSeriesData[axis] = []
                strongSelf.fftMagnitudes[axis] = []
            }
            await strongSelf.updateIdleStateDisplayValues()
            await strongSelf.resetRMSValuesAndAttitude()
            if strongSelf.useLinearAccelerationSetting {
                await strongSelf.startLiveAttitudeMonitoring()
            }
        }
    }

    deinit {
        stopLiveAttitudeMonitoring() // This is synchronous
        dataFetchTimer?.invalidate()
        durationCountdownTimer?.invalidate()
        preRecordingDelayTimer?.invalidate()
        if isRecording || measurementState == .preRecordingCountdown {
            recorder.stopRecording()
        }
    }

    private func updateSettingsDependentState() {
        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.measurementState == .idle && !strongSelf.isRecording {
                strongSelf.recorder.motionSessionPublic.samplingRate = strongSelf.actualCoreMotionRequestRate
                await strongSelf.updateIdleStateDisplayValues()
            }
        }
    }

    private func updateIdleStateDisplayValues() async {
        // Since this func updates @Published properties, it should be on the MainActor.
        // Task { @MainActor in } // No, this is already MainActor if called from MainActor context or is @MainActor func
        self.timeLeft = currentInitialTimeLeft
        self.axisRanges.maxX = currentEffectiveMaxGraphDuration
        self.elapsedTime = 0
    }

    // MARK: - Helper Methods
    private func resetRMSValuesAndAttitude() async {
        // Task { @MainActor in } // No, this is already MainActor if called from MainActor context or is @MainActor func
        self.rmsX = 0.0; self.rmsY = 0.0; self.rmsZ = 0.0
        // This inner Task is to ensure roll/pitch are set on MainActor, which is good practice.
        await Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.currentRoll = 0.0; strongSelf.currentPitch = 0.0
        }.value
    }

    private func findPeakFrequency(for axis: Axis) -> Double? {
        guard let magnitudes = fftMagnitudes[axis], !magnitudes.isEmpty,
              !fftFrequencies.isEmpty, magnitudes.count == fftFrequencies.count else { return nil }
        return zip(fftFrequencies, magnitudes).max(by: { $0.1 < $1.1 })?.0
    }

    private func toggleLiveAttitudeBasedOnSetting() {
        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.useLinearAccelerationSetting {
                await strongSelf.startLiveAttitudeMonitoring()
            } else {
                strongSelf.stopLiveAttitudeMonitoring()
            }
        }
    }

    func startLiveAttitudeMonitoring() async {
        guard useLinearAccelerationSetting, !isLiveAttitudeMonitoringActive, motionSessionForLiveAttitude.isDeviceMotionAvailable else { return }
        isLiveAttitudeMonitoringActive = true
        motionSessionForLiveAttitude.provideUserAccelerationFromDeviceMotion = true
        _ = motionSessionForLiveAttitude.startDeviceMotionUpdates(for: self, interval: liveAttitudeUpdateInterval) { [weak self] (payload, error) in
            guard let strongSelf = self, strongSelf.isLiveAttitudeMonitoringActive, let dataPayload = payload, error == nil else { return }
            Task { @MainActor in // This Task is for the CM completion handler
                strongSelf.currentRoll = dataPayload.attitude.roll * 180.0 / .pi
                strongSelf.currentPitch = dataPayload.attitude.pitch * 180.0 / .pi
            }
        }
    }

    func stopLiveAttitudeMonitoring() {
        guard isLiveAttitudeMonitoringActive else { return }
        isLiveAttitudeMonitoringActive = false
        motionSessionForLiveAttitude.stopDeviceMotionUpdates(for: self)
        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.currentRoll = 0.0
            strongSelf.currentPitch = 0.0
        }
    }

    // MARK: - Main Measurement Control
    @MainActor
    func startMeasurement() async {
        guard measurementState == .idle else { return }
        await resetDataForNewRecording()

        if recordingStartDelaySetting > 0 {
            measurementState = .preRecordingCountdown
            isRecording = false
            timeLeft = recordingStartDelaySetting
            preRecordingPhaseStartTime = Date()
            axisRanges.maxX = recordingStartDelaySetting

            preRecordingDelayTimer?.invalidate()
            preRecordingDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timerRef in
                Task { @MainActor in
                    guard let strongSelf = self, strongSelf.measurementState == .preRecordingCountdown else { // Use strongSelf
                        timerRef.invalidate(); return
                    }
                    if let delayStartTime = strongSelf.preRecordingPhaseStartTime {
                        let elapsedDelay = Date().timeIntervalSince(delayStartTime)
                        strongSelf.timeLeft = max(0, strongSelf.recordingStartDelaySetting - elapsedDelay)
                        if elapsedDelay >= strongSelf.recordingStartDelaySetting {
                            timerRef.invalidate(); strongSelf.preRecordingDelayTimer = nil
                            await strongSelf.beginActualRecording()
                        }
                    } else {
                        timerRef.invalidate(); strongSelf.preRecordingDelayTimer = nil
                        strongSelf.measurementState = .idle
                    }
                }
            }
        } else {
            await beginActualRecording()
        }
    }

    @MainActor
    private func beginActualRecording() async {
        measurementState = .recording
        isRecording = true

        recordingActualStartTime = Date()
        elapsedTime = 0.0
        timeLeft = autoStopRecordingEnabled && measurementDurationSetting > 0 ? measurementDurationSetting : 0

        axisRanges.minX = 0
        axisRanges.maxX = currentEffectiveMaxGraphDuration

        lastProcessedSampleTimestamp = 0; calculatedActualAverageSamplingRateForFFT = nil

        recorder.useDeviceMotionForData = useLinearAccelerationSetting
        if recorder.useDeviceMotionForData {
             recorder.motionSessionPublic.provideUserAccelerationFromDeviceMotion = useLinearAccelerationSetting
        }
        recorder.motionSessionPublic.samplingRate = self.actualCoreMotionRequestRate
        recorder.clear(); recorder.startRecording()

        let fetchInterval = 1.0 / Double(max(100, self.actualCoreMotionRequestRate))
        dataFetchTimer?.invalidate()
        dataFetchTimer = Timer.scheduledTimer(withTimeInterval:max(0.005,fetchInterval/2.0),repeats:true){ [weak self] timerRef in
            Task { @MainActor in
                guard let strongSelf = self else { timerRef.invalidate(); return }
                strongSelf.captureNewSamples()
            }
        }

        durationCountdownTimer?.invalidate()
        let timerInterval = 0.05
        durationCountdownTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] timerRef in
            Task { @MainActor in
                guard let strongSelf = self, strongSelf.isRecording else {
                    timerRef.invalidate(); return
                }
                if let recStartTime = strongSelf.recordingActualStartTime {
                    strongSelf.elapsedTime = Date().timeIntervalSince(recStartTime)
                } else {
                    strongSelf.elapsedTime += timerInterval
                }

                if strongSelf.autoStopRecordingEnabled && strongSelf.measurementDurationSetting > 0 {
                    strongSelf.timeLeft = max(0, strongSelf.measurementDurationSetting - strongSelf.elapsedTime)
                }

                if strongSelf.measurementState == .recording {
                    let cmt = strongSelf.timeSeriesData[Axis.x]?.last?.timestamp ?? strongSelf.elapsedTime
                    if strongSelf.autoStopRecordingEnabled && strongSelf.measurementDurationSetting > 0 {
                        strongSelf.axisRanges.minX = 0
                        strongSelf.axisRanges.maxX = max(strongSelf.measurementDurationSetting, cmt + 0.2)
                    } else {
                        let windowDuration = 10.0
                        strongSelf.axisRanges.minX = max(0, strongSelf.elapsedTime - windowDuration)
                        strongSelf.axisRanges.maxX = strongSelf.elapsedTime + 0.2
                    }
                }
                if strongSelf.autoStopRecordingEnabled && strongSelf.measurementDurationSetting > 0 && strongSelf.elapsedTime >= strongSelf.measurementDurationSetting {
                    await strongSelf.stopMeasurement()
                }
            }
        }
    }

    @MainActor
    func stopMeasurement() async {
        let wasPreRecording = (measurementState == .preRecordingCountdown)

        preRecordingDelayTimer?.invalidate(); preRecordingDelayTimer = nil
        durationCountdownTimer?.invalidate(); durationCountdownTimer = nil
        dataFetchTimer?.invalidate(); dataFetchTimer = nil

        if isRecording {
            recorder.stopRecording()
            Task { @MainActor [weak self] in
                 guard let strongSelf = self else { return }
                 strongSelf.captureNewSamples()
            }
        }

        isRecording = false
        measurementState = wasPreRecording ? .idle : .completed

        if !wasPreRecording {
            if let startTime = recordingActualStartTime {
                elapsedTime = Date().timeIntervalSince(startTime)
            }
            if autoStopRecordingEnabled && measurementDurationSetting > 0 {
                timeLeft = max(0, measurementDurationSetting - elapsedTime)
            } else {
                timeLeft = 0
            }

            let finalMaxTimestamp = Axis.allCases.compactMap { timeSeriesData[$0]?.last?.timestamp }.max() ?? elapsedTime
            axisRanges.minX = 0
            axisRanges.maxX = max(finalMaxTimestamp, currentEffectiveMaxGraphDuration)

            if collectedSamplesCount > 0 {
                self.rmsX = calculateOverallRMS(for: .x)
                self.rmsY = calculateOverallRMS(for: .y)
                self.rmsZ = calculateOverallRMS(for: .z)
            } else {
                await resetRMSValuesAndAttitude()
            }

            calculateActualAverageRate()
            if collectedSamplesCount > 0 {
                await computeFFT()
            } else {
                isFFTReady = false
                calculatedActualAverageSamplingRateForFFT = nil
            }
        } else {
            await updateIdleStateDisplayValues()
        }

        recordingActualStartTime = nil
        preRecordingPhaseStartTime = nil
        if useLinearAccelerationSetting {
             await startLiveAttitudeMonitoring()
        }
    }

    @MainActor
    func resetMeasurement() async {
        if isRecording || measurementState == .preRecordingCountdown {
            await stopMeasurement()
        }
        await resetDataForNewRecording()
        measurementState = .idle
        isFFTReady = false
        await updateIdleStateDisplayValues()

        latestX = 0; latestY = 0; latestZ = 0
        calculatedActualAverageSamplingRateForFFT = nil
        // currentRoll/Pitch are reset within resetDataForNewRecording via resetRMSValuesAndAttitude
        recordingActualStartTime = nil
        preRecordingPhaseStartTime = nil
        if useLinearAccelerationSetting {
            await startLiveAttitudeMonitoring()
        } else {
            stopLiveAttitudeMonitoring()
        }
    }

    @MainActor
    private func resetDataForNewRecording() async {
        Axis.allCases.forEach { axis in
            timeSeriesData[axis]?.removeAll()
            fftMagnitudes[axis]?.removeAll()
        }
        fftFrequencies.removeAll()
        lastProcessedSampleTimestamp = 0
        await resetRMSValuesAndAttitude()
    }

    @MainActor
    private func captureNewSamples() {
        guard measurementState == .recording ||
              (measurementState == .completed && dataFetchTimer == nil && !isRecording)
        else { return }

        let allRecordedData = recorder.getRecordedData()
        let newSamples = allRecordedData.filter { $0.timestamp > self.lastProcessedSampleTimestamp }
        guard !newSamples.isEmpty else { return }

        var currentMaxAbsY = abs(axisRanges.maxY)
        for sample in newSamples {
            timeSeriesData[Axis.x]?.append(DataPoint(timestamp: sample.timestamp, value: sample.x))
            timeSeriesData[Axis.y]?.append(DataPoint(timestamp: sample.timestamp, value: sample.y))
            timeSeriesData[Axis.z]?.append(DataPoint(timestamp: sample.timestamp, value: sample.z))
            currentMaxAbsY = max(currentMaxAbsY, abs(sample.x), abs(sample.y), abs(sample.z))
            self.latestX = sample.x; self.latestY = sample.y; self.latestZ = sample.z
        }
        if let lastTimestamp = newSamples.last?.timestamp { self.lastProcessedSampleTimestamp = lastTimestamp }

        if measurementState == .recording {
             let newDynamicMaxY = currentMaxAbsY.isFinite && currentMaxAbsY > 1e-5 ? currentMaxAbsY : 1.0
             axisRanges.minY = -newDynamicMaxY; axisRanges.maxY = newDynamicMaxY
        }
    }

    private func calculateOverallRMS(for axis: Axis) -> Double {
        guard let dataPoints = timeSeriesData[axis], !dataPoints.isEmpty else { return 0.0 }
        let values = dataPoints.map { $0.value }
        let sumOfSquares = values.reduce(0.0) { $0 + ($1 * $1) }
        return sqrt(sumOfSquares / Double(values.count))
    }

    private func calculateActualAverageRate() {
        guard let xDataPoints = self.timeSeriesData[Axis.x], xDataPoints.count > 1,
              let firstTimestamp = xDataPoints.first?.timestamp,
              let lastTimestamp = xDataPoints.last?.timestamp,
              lastTimestamp > firstTimestamp else {
            self.calculatedActualAverageSamplingRateForFFT = Double(self.actualCoreMotionRequestRate)
            return
        }
        let numberOfActualSamples = Double(xDataPoints.count)
        let actualRecordingDuration = lastTimestamp - firstTimestamp
        let rate = (numberOfActualSamples - 1.0) / actualRecordingDuration
        self.calculatedActualAverageSamplingRateForFFT = (rate > 0 && rate.isFinite) ? rate : Double(self.actualCoreMotionRequestRate)
    }

    @MainActor
    func computeFFT() async { // Marked async
        guard collectedSamplesCount > 0, let rateForFFT = self.calculatedActualAverageSamplingRateForFFT else {isFFTReady = false; return}
        isFFTReady = false
        let xV = (timeSeriesData[Axis.x] ?? []).map{$0.value}
        let yV = (timeSeriesData[Axis.y] ?? []).map{$0.value}
        let zV = (timeSeriesData[Axis.z] ?? []).map{$0.value}
        let analyzer = self.fftAnalyzer

        await Task.detached(priority: .userInitiated) { [weak self, analyzer, xV, yV, zV, rateForFFT] in
            guard let strongSelf = self else { return }
            let rX = analyzer.performFFT(input:xV, samplingRate:rateForFFT)
            let rY = analyzer.performFFT(input:yV, samplingRate:rateForFFT)
            let rZ = analyzer.performFFT(input:zV, samplingRate:rateForFFT)
            await MainActor.run {
                strongSelf.fftFrequencies=rX.frequencies
                strongSelf.fftMagnitudes[Axis.x]=rX.magnitude
                strongSelf.fftMagnitudes[Axis.y]=rY.magnitude
                strongSelf.fftMagnitudes[Axis.z]=rZ.magnitude
                strongSelf.isFFTReady = true
            }
        }.value
    }

    @MainActor func toggleAxisVisibility(_ axis: Axis) {
        if activeAxes.contains(axis){ if activeAxes.count > 1{activeAxes.remove(axis)}} else{activeAxes.insert(axis)}
    }

    func exportCSV() { // Not marked @MainActor, but calls presentShareSheet which needs main actor
        guard collectedSamplesCount > 0 else { print("No data to export."); return }
        var csvString = "Timestamp,X,Y,Z\n" // Corrected newline
        let nf = NumberFormatter(); nf.minimumFractionDigits = 4; nf.maximumFractionDigits = 8; nf.decimalSeparator = "."; nf.numberStyle = .decimal
        
        // This data access should ideally be on the MainActor if timeSeriesData can be modified concurrently.
        // However, since it's an ObservableObject, changes usually come from @MainActor already.
        // For safety in a non-@MainActor func, one might wrap this data access.
        // But given the context, assume it's called from a UI context that's already main.
        let xData = timeSeriesData[Axis.x] ?? []
        let yData = timeSeriesData[Axis.y] ?? []
        let zData = timeSeriesData[Axis.z] ?? []
        let rowCount = [xData.count, yData.count, zData.count].min() ?? 0
        
        for i in 0..<rowCount {
            let ts = xData[i].timestamp
            let xVal = xData[i].value
            let yVal = yData[i].value
            let zVal = zData[i].value
            
            let xStr = nf.string(from: NSNumber(value: xVal)) ?? "\(xVal)"
            let yStr = nf.string(from: NSNumber(value: yVal)) ?? "\(yVal)"
            let zStr = nf.string(from: NSNumber(value: zVal)) ?? "\(zVal)"
            
            csvString += "\(String(format: "%.4f", ts)),\(xStr),\(yStr),\(zStr)\n" // Corrected newline
        }
        let df = DateFormatter(); df.dateFormat="yyyyMMdd_HHmmss"; let fn="DynaVibe_RawData_\(df.string(from: Date())).csv"
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { print("No docs dir."); return }
        let fileURL = docsDir.appendingPathComponent(fn)
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            Task { @MainActor [weak self] in // Ensure presentShareSheet is called on MainActor
                guard let strongSelf = self else { return }
                strongSelf.presentShareSheet(for: fileURL)
            }
        }
        catch { print("CSV write failed: \(error.localizedDescription)") }
    }

    private func presentShareSheet(for url: URL) { // Not marked @MainActor, but uses DispatchQueue.main.async
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                  let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view; popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width:0, height:0); popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }
}
