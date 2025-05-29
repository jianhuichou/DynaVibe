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
        didSet { self.updateSettingsDependentState() }
    }
    @AppStorage("measurementDurationSetting") var measurementDurationSetting: Double = 10.0 {
        didSet { self.updateSettingsDependentState() }
    }
    @AppStorage("recordingStartDelaySetting") var recordingStartDelaySetting: Double = 3.0 {
        didSet { self.updateSettingsDependentState() }
    }
    @AppStorage("autoStopRecordingEnabled") var autoStopRecordingEnabled: Bool = true {
        didSet { self.updateSettingsDependentState() }
    }
    @AppStorage("useLinearAccelerationSetting") var useLinearAccelerationSetting: Bool = false {
        didSet { if oldValue != self.useLinearAccelerationSetting { self.toggleLiveAttitudeBasedOnSetting() } }
    }

    // MARK: - Computed Properties
    var actualCoreMotionRequestRate: Int {
        switch self.samplingRateSettingStorage {
        case 0: return 1000
        case 32, 64, 128: return self.samplingRateSettingStorage
        default: return 128
        }
    }
    var currentStatusText: String {
        switch self.measurementState {
        case .idle: return "Idle"
        case .preRecordingCountdown: return "Starting in..."
        case .recording: return self.autoStopRecordingEnabled && self.measurementDurationSetting > 0 ? "Recording..." : "Recording (Manual Stop)"
        case .completed: return "Completed"
        }
    }
    var currentEffectiveMaxGraphDuration: Double {
        self.autoStopRecordingEnabled && self.measurementDurationSetting > 0 ? self.measurementDurationSetting : 10.0
    }
    var currentInitialTimeLeft: Double {
        self.recordingStartDelaySetting > 0 ? self.recordingStartDelaySetting : (self.autoStopRecordingEnabled && self.measurementDurationSetting > 0 ? self.measurementDurationSetting : 0)
    }
    var collectedSamplesCount: Int { self.timeSeriesData[Axis.x]?.count ?? 0 }
    var minX: Double? { self.timeSeriesData[Axis.x]?.min(by: { $0.value < $1.value })?.value }
    var maxX: Double? { self.timeSeriesData[Axis.x]?.max(by: { $0.value < $1.value })?.value }
    var minY: Double? { self.timeSeriesData[Axis.y]?.min(by: { $0.value < $1.value })?.value }
    var maxY: Double? { self.timeSeriesData[Axis.y]?.max(by: { $0.value < $1.value })?.value }
    var minZ: Double? { self.timeSeriesData[Axis.z]?.min(by: { $0.value < $1.value })?.value }
    var maxZ: Double? { self.timeSeriesData[Axis.z]?.max(by: { $0.value < $1.value })?.value }
    var peakFrequencyX: Double? { self.findPeakFrequency(for: .x) }
    var peakFrequencyY: Double? { self.findPeakFrequency(for: .y) }
    var peakFrequencyZ: Double? { self.findPeakFrequency(for: .z) }
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
        self.recorder.motionSessionPublic.samplingRate = self.actualCoreMotionRequestRate
        Axis.allCases.forEach { axis in
            self.timeSeriesData[axis] = []
            self.fftMagnitudes[axis] = []
        }
        self.updateIdleStateDisplayValues()
        self.resetRMSValuesAndAttitude()
        if self.useLinearAccelerationSetting {
            self.startLiveAttitudeMonitoring()
        }
    }

    deinit {
        self.stopLiveAttitudeMonitoring()
        self.dataFetchTimer?.invalidate()
        self.durationCountdownTimer?.invalidate()
        self.preRecordingDelayTimer?.invalidate()
        if self.isRecording || self.measurementState == .preRecordingCountdown {
            self.recorder.stopRecording()
        }
    }
    
    private func updateSettingsDependentState() {
        if self.measurementState == .idle && !self.isRecording {
            self.recorder.motionSessionPublic.samplingRate = self.actualCoreMotionRequestRate
            self.updateIdleStateDisplayValues()
        }
    }

    private func updateIdleStateDisplayValues() {
        self.timeLeft = self.currentInitialTimeLeft
        self.axisRanges.maxX = self.currentEffectiveMaxGraphDuration
        self.elapsedTime = 0
    }

    // MARK: - Helper Methods
    private func resetRMSValuesAndAttitude() {
        self.rmsX = 0.0; self.rmsY = 0.0; self.rmsZ = 0.0
        Task { @MainActor [weak self] in // Added [weak self]
            guard let strongSelf = self else { return }
            strongSelf.currentRoll = 0.0; strongSelf.currentPitch = 0.0
        }
    }

    private func findPeakFrequency(for axis: Axis) -> Double? {
        guard let magnitudes = self.fftMagnitudes[axis], !magnitudes.isEmpty,
              !self.fftFrequencies.isEmpty, magnitudes.count == self.fftFrequencies.count else { return nil }
        return zip(self.fftFrequencies, magnitudes).max(by: { $0.1 < $1.1 })?.0
    }

    private func toggleLiveAttitudeBasedOnSetting() {
        if self.useLinearAccelerationSetting { self.startLiveAttitudeMonitoring() }
        else { self.stopLiveAttitudeMonitoring() }
    }

    func startLiveAttitudeMonitoring() {
        guard self.useLinearAccelerationSetting, !self.isLiveAttitudeMonitoringActive, self.motionSessionForLiveAttitude.isDeviceMotionAvailable else { return }
        self.isLiveAttitudeMonitoringActive = true
        self.motionSessionForLiveAttitude.provideUserAccelerationFromDeviceMotion = true
        _ = self.motionSessionForLiveAttitude.startDeviceMotionUpdates(for: self, interval: self.liveAttitudeUpdateInterval) { [weak self] (payload, error) in
            guard let strongSelf = self, strongSelf.isLiveAttitudeMonitoringActive, let dataPayload = payload, error == nil else { return }
            Task { @MainActor [weak strongSelf] in // Nested Task, capture strongSelf weakly
                guard let sSelf = strongSelf else { return }
                sSelf.currentRoll = dataPayload.attitude.roll * 180.0 / .pi
                sSelf.currentPitch = dataPayload.attitude.pitch * 180.0 / .pi
            }
        }
    }

    func stopLiveAttitudeMonitoring() {
        guard self.isLiveAttitudeMonitoringActive else { return }
        self.isLiveAttitudeMonitoringActive = false
        self.motionSessionForLiveAttitude.stopDeviceMotionUpdates(for: self)
        Task { @MainActor [weak self] in // Added [weak self]
            guard let strongSelf = self else { return }
            strongSelf.currentRoll = 0.0
            strongSelf.currentPitch = 0.0
        }
    }

    // MARK: - Main Measurement Control
    @MainActor
    func startMeasurement() {
        guard self.measurementState == .idle else { return }
        self.resetDataForNewRecording() // This line should be fine as it's directly in the method body
        
        if self.recordingStartDelaySetting > 0 {
            self.measurementState = .preRecordingCountdown
            self.isRecording = false
            self.timeLeft = self.recordingStartDelaySetting
            self.preRecordingPhaseStartTime = Date()
            self.axisRanges.maxX = self.recordingStartDelaySetting
            
            self.preRecordingDelayTimer?.invalidate()
            self.preRecordingDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timerRef in
                Task { @MainActor [weak self] in // Added [weak self] to inner Task
                    guard let strongSelf = self else { timerRef.invalidate(); return } // Ensure self is valid for Task
                    guard strongSelf.measurementState == .preRecordingCountdown else {
                        timerRef.invalidate(); return
                    }
                    if let delayStartTime = strongSelf.preRecordingPhaseStartTime {
                        let elapsedDelay = Date().timeIntervalSince(delayStartTime)
                        strongSelf.timeLeft = max(0, strongSelf.recordingStartDelaySetting - elapsedDelay)
                        if elapsedDelay >= strongSelf.recordingStartDelaySetting {
                            timerRef.invalidate(); strongSelf.preRecordingDelayTimer = nil
                            strongSelf.beginActualRecording()
                        }
                    } else {
                        timerRef.invalidate(); strongSelf.preRecordingDelayTimer = nil
                        // If preRecordingPhaseStartTime was nil, something went wrong, reset to idle.
                        strongSelf.measurementState = .idle 
                    }
                }
            }
        } else {
            self.beginActualRecording() // This is a direct call, should be fine
        }
    }

    @MainActor
    private func beginActualRecording() {
        self.measurementState = .recording
        self.isRecording = true
        
        self.recordingActualStartTime = Date()
        self.elapsedTime = 0.0
        self.timeLeft = self.autoStopRecordingEnabled && self.measurementDurationSetting > 0 ? self.measurementDurationSetting : 0
        
        self.axisRanges.minX = 0
        self.axisRanges.maxX = self.currentEffectiveMaxGraphDuration

        self.lastProcessedSampleTimestamp = 0; self.calculatedActualAverageSamplingRateForFFT = nil
        
        self.recorder.useDeviceMotionForData = self.useLinearAccelerationSetting
        if self.recorder.useDeviceMotionForData {
             self.recorder.motionSessionPublic.provideUserAccelerationFromDeviceMotion = self.useLinearAccelerationSetting
        }
        self.recorder.motionSessionPublic.samplingRate = self.actualCoreMotionRequestRate
        self.recorder.clear(); self.recorder.startRecording()

        let fetchInterval = 1.0 / Double(max(100, self.actualCoreMotionRequestRate))
        self.dataFetchTimer?.invalidate()
        self.dataFetchTimer = Timer.scheduledTimer(withTimeInterval:max(0.005,fetchInterval/2.0),repeats:true){ [weak self] _ in
            Task { @MainActor in
                guard let strongSelf = self else { return }
                strongSelf.captureNewSamples()
            }
        }
        
        self.durationCountdownTimer?.invalidate()
        let timerInterval = 0.05
        self.durationCountdownTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] tR in
            Task { @MainActor in
                guard let strongSelf = self, strongSelf.isRecording else { tR.invalidate(); return }
                if let rST = strongSelf.recordingActualStartTime { strongSelf.elapsedTime = Date().timeIntervalSince(rST) } else { strongSelf.elapsedTime += timerInterval }
                if strongSelf.autoStopRecordingEnabled && strongSelf.measurementDurationSetting > 0 { strongSelf.timeLeft = max(0, strongSelf.measurementDurationSetting - strongSelf.elapsedTime) }
                if strongSelf.measurementState == .recording {
                    let cmt = strongSelf.timeSeriesData[Axis.x]?.last?.timestamp ?? strongSelf.elapsedTime
                    if strongSelf.autoStopRecordingEnabled && strongSelf.measurementDurationSetting > 0 {
                        strongSelf.axisRanges.minX = 0; strongSelf.axisRanges.maxX = max(strongSelf.measurementDurationSetting, cmt + 0.2)
                    } else { let windowDur = 10.0; strongSelf.axisRanges.minX = max(0, strongSelf.elapsedTime - windowDur); strongSelf.axisRanges.maxX = strongSelf.elapsedTime + 0.2 }
                }
                if strongSelf.autoStopRecordingEnabled && strongSelf.measurementDurationSetting > 0 && strongSelf.elapsedTime >= strongSelf.measurementDurationSetting { strongSelf.stopMeasurement() }
            }
        }}
    }
    
    @MainActor
    func stopMeasurement() {
        let wasPreRecording = (self.measurementState == .preRecordingCountdown)
        
        self.preRecordingDelayTimer?.invalidate(); self.preRecordingDelayTimer=nil
        self.durationCountdownTimer?.invalidate(); self.durationCountdownTimer=nil
        self.dataFetchTimer?.invalidate(); self.dataFetchTimer=nil
        
        if self.isRecording{
            self.recorder.stopRecording()
            Task{ @MainActor [weak self] in // Added [weak self]
                guard let strongSelf = self else { return }
                strongSelf.captureNewSamples()
            }
        }
        self.isRecording=false
        self.measurementState = wasPreRecording ? .idle : .completed
        
        if !wasPreRecording{
            if let sT=self.recordingActualStartTime{self.elapsedTime = Date().timeIntervalSince(sT)}
            if self.autoStopRecordingEnabled && self.measurementDurationSetting > 0 {self.timeLeft = max(0,self.measurementDurationSetting-self.elapsedTime)} else {self.timeLeft=0}
            let fMT = Axis.allCases.compactMap{ ax in self.timeSeriesData[ax]?.last?.timestamp }.max() ?? self.elapsedTime
            self.axisRanges.minX = 0
            self.axisRanges.maxX = max(fMT,self.currentEffectiveMaxGraphDuration)
            if self.collectedSamplesCount > 0 {
                self.rmsX = self.calculateOverallRMS(for:.x)
                self.rmsY = self.calculateOverallRMS(for:.y)
                self.rmsZ = self.calculateOverallRMS(for:.z)
            } else {
                self.resetRMSValuesAndAttitude()
            }
            self.calculateActualAverageRate()
            if self.collectedSamplesCount > 0 { self.computeFFT() } else { self.isFFTReady=false; self.calculatedActualAverageSamplingRateForFFT=nil }
        } else {
            self.updateIdleStateDisplayValues()
        }
        self.recordingActualStartTime=nil
        self.preRecordingPhaseStartTime=nil
        if self.useLinearAccelerationSetting {
            self.startLiveAttitudeMonitoring() // This should be fine as it's a direct call
        }
    }

    @MainActor
    func resetMeasurement() {
        if self.isRecording || self.measurementState == .preRecordingCountdown { self.stopMeasurement() }; // Direct call, should be fine
        self.resetDataForNewRecording() // Direct call, should be fine
        self.measurementState = .idle; self.isFFTReady=false; self.elapsedTime=0
        self.updateIdleStateDisplayValues() // Direct call, should be fine
        self.latestX=0; self.latestY=0; self.latestZ=0; self.calculatedActualAverageSamplingRateForFFT=nil; self.currentRoll=0; self.currentPitch=0
        self.recordingActualStartTime=nil; self.preRecordingPhaseStartTime=nil
        if self.useLinearAccelerationSetting { self.startLiveAttitudeMonitoring() } // Direct call, should be fine
        else { self.stopLiveAttitudeMonitoring() } // Direct call, should be fine
    }

    @MainActor
    func resetDataForNewRecording() {
        Axis.allCases.forEach{ a in self.timeSeriesData[a]?.removeAll(); self.fftMagnitudes[a]?.removeAll() }
        self.fftFrequencies.removeAll(); self.lastProcessedSampleTimestamp=0
        self.resetRMSValuesAndAttitude() // Direct call, should be fine
    }
    
    @MainActor
    func captureNewSamples() {
        guard self.measurementState == .recording || (self.measurementState == .completed && self.dataFetchTimer == nil && !self.isRecording) else { return }
        let aRD = self.recorder.getRecordedData(); let nS = aRD.filter{ $0.timestamp > self.lastProcessedSampleTimestamp }; guard !nS.isEmpty else { return }
        var cMAY = abs(self.axisRanges.maxY)
        for s in nS {
            self.timeSeriesData[Axis.x]?.append(.init(timestamp:s.timestamp,value:s.x))
            self.timeSeriesData[Axis.y]?.append(.init(timestamp:s.timestamp,value:s.y))
            self.timeSeriesData[Axis.z]?.append(.init(timestamp:s.timestamp,value:s.z))
            cMAY = max(cMAY,abs(s.x),abs(s.y),abs(s.z))
            self.latestX=s.x; self.latestY=s.y; self.latestZ=s.z
        }
        if let lastTimestamp = nS.last?.timestamp {
            self.lastProcessedSampleTimestamp = lastTimestamp
        }
        
        if self.measurementState == .recording {
            let newDynamicMaxY = (cMAY.isFinite && cMAY > 0.00001) ? cMAY : 1.0 // Use a small epsilon for zero-check
            self.axisRanges.minY = -newDynamicMaxY
            self.axisRanges.maxY = newDynamicMaxY
        }
    }
    
    private func calculateOverallRMS(for axis: Axis) -> Double {
        guard let dPs = self.timeSeriesData[axis], !dPs.isEmpty else { return 0.0 }
        let v = dPs.map{ $0.value }; let sOS = v.reduce(0.0){ $0 + ($1*$1) }; return sqrt(sOS/Double(v.count))
    }
    
    private func calculateActualAverageRate() {
        guard let xDataPoints = self.timeSeriesData[Axis.x], xDataPoints.count > 1,
              let firstTimestamp = xDataPoints.first?.timestamp,
              let lastTimestamp = xDataPoints.last?.timestamp,
              lastTimestamp > firstTimestamp else {
            self.calculatedActualAverageSamplingRateForFFT = Double(self.actualCoreMotionRequestRate) // Direct access, should be fine
            return
        }
        let numberOfActualSamples = Double(xDataPoints.count)
        let actualRecordingDuration = lastTimestamp - firstTimestamp
        let rate = (numberOfActualSamples - 1.0) / actualRecordingDuration
        self.calculatedActualAverageSamplingRateForFFT = (rate > 0 && rate.isFinite) ? rate : Double(self.actualCoreMotionRequestRate) // Direct access, should be fine
    }
    
    @MainActor
    func computeFFT() {
        guard self.collectedSamplesCount > 0, let rateForFFT = self.calculatedActualAverageSamplingRateForFFT else { self.isFFTReady = false; return }
        self.isFFTReady = false
        let xV = (self.timeSeriesData[Axis.x] ?? []).map{ $0.value }
        let yV = (self.timeSeriesData[Axis.y] ?? []).map{ $0.value }
        let zV = (self.timeSeriesData[Axis.z] ?? []).map{ $0.value }
        let analyzer = self.fftAnalyzer // Local copy, fine
        Task.detached(priority: .userInitiated) { [weak self, analyzer] in // analyzer is captured
            guard let strongSelf = self else { return }
            let rX = analyzer.performFFT(input:xV, samplingRate:rateForFFT)
            let rY = analyzer.performFFT(input:yV, samplingRate:rateForFFT)
            let rZ = analyzer.performFFT(input:zV, samplingRate:rateForFFT)
            await MainActor.run {
                strongSelf.fftFrequencies = rX.frequencies
                strongSelf.fftMagnitudes[Axis.x] = rX.magnitude
                strongSelf.fftMagnitudes[Axis.y] = rY.magnitude
                strongSelf.fftMagnitudes[Axis.z] = rZ.magnitude
                strongSelf.isFFTReady = true
            }
        }
    }

    @MainActor func toggleAxisVisibility(_ axis: Axis) {
        if self.activeAxes.contains(axis){ if self.activeAxes.count > 1{self.activeAxes.remove(axis)}} else{self.activeAxes.insert(axis)}
    }
    
    @MainActor
    func exportCSV() {
        guard self.collectedSamplesCount > 0 else {
            print("AccelerationViewModel: No data to export.")
            // Optionally, inform the user via UI
            return
        }

        let csvHeader = "Timestamp,X,Y,Z\n"
        var csvString = csvHeader
        
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 4
        numberFormatter.maximumFractionDigits = 8
        numberFormatter.decimalSeparator = "."
        numberFormatter.numberStyle = .decimal

        let xSamples: [DataPoint] = self.timeSeriesData[Axis.x] ?? []
        let ySamples: [DataPoint] = self.timeSeriesData[Axis.y] ?? []
        let zSamples: [DataPoint] = self.timeSeriesData[Axis.z] ?? []
        let rowCount = [xSamples.count, ySamples.count, zSamples.count].min() ?? 0
        
        for i in 0..<rowCount {
            // Already guarded by rowCount, but direct access is fine.
            let ts = xSamples[i].timestamp
            let xVal = xSamples[i].value
            let yVal = ySamples[i].value
            let zVal = zSamples[i].value
            
            let xStr = numberFormatter.string(from: NSNumber(value: xVal)) ?? "\(xVal)"
            let yStr = numberFormatter.string(from: NSNumber(value: yVal)) ?? "\(yVal)"
            let zStr = numberFormatter.string(from: NSNumber(value: zVal)) ?? "\(zVal)"
            
            csvString += "\(String(format: "%.4f", ts)),\(xStr),\(yStr),\(zStr)\n"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "DynaVibe_RawData_\(dateFormatter.string(from: Date())).csv"
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("AccelerationViewModel: Failed to access documents directory.")
            // Optionally, inform the user via UI
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("AccelerationViewModel: CSV successfully saved to \(fileURL.path)")
            self.presentShareSheet(for: fileURL)
        } catch {
            print("AccelerationViewModel: CSV write failed - \(error.localizedDescription)")
            // Optionally, inform the user via UI about the failure
        }
    }

    @MainActor
    private func presentShareSheet(for url: URL) {
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

