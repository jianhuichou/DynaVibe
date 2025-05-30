// ViewModels/AccelerationViewModel.swift
import Foundation
import SwiftUI
import Combine
import CoreMotion

// Ensure MultiLineGraphView (for .AxisRanges), DataPoint, Axis types are accessible
// from their respective files (e.g., UI/MultiLineGraphView.swift, Models/DataPoint.swift, Shared/AxisAndLegend.swift)

// Enum to select between raw and weighted time series for graph display
public enum TimeDataType: String, CaseIterable, Identifiable { // Made public for RealTimeDataView
    case raw = "Raw Time History"
    case weighted = "Weighted Time History"
    public var id: String { self.rawValue }
}

final class AccelerationViewModel: MotionSessionReceiver, ObservableObject {

    // MARK: - Published State
    @Published var displayTimeDataType: TimeDataType = .raw // User's choice for time data display
    @Published var latestX: Double = 0.0
    @Published var latestY: Double = 0.0
    @Published var latestZ: Double = 0.0
    @Published var timeSeriesData: [Axis: [DataPoint]] = [:]
    @Published var fftFrequencies: [Double] = []
    @Published var fftMagnitudes: [Axis: [Double]] = [:]
    @Published var rmsX: Double = 0.0 // Unweighted RMS
    @Published var rmsY: Double = 0.0 // Unweighted RMS
    @Published var rmsZ: Double = 0.0 // Unweighted RMS
    @Published var weightedRmsX: Double = 0.0
    @Published var weightedRmsY: Double = 0.0
    @Published var weightedRmsZ: Double = 0.0

    // For MTVV (Maximum Transient Vibration Value) - typically per axis
    @Published var mtvvX: Double = 0.0
    @Published var mtvvY: Double = 0.0
    @Published var mtvvZ: Double = 0.0

    // For VDV (Vibration Dose Value) - can be per axis or combined.
    @Published var vdvX: Double = 0.0
    @Published var vdvY: Double = 0.0
    @Published var vdvZ: Double = 0.0
    @Published var vdvTotal: Double = 0.0 // Or vdvOverall

    @Published var weightedTimeSeriesX: [Double] = []
    @Published var weightedTimeSeriesY: [Double] = []
    @Published var weightedTimeSeriesZ: [Double] = []

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
    // @Published var selectedWeightingType: WeightingType = .none // Replaced by AppStorage-backed computed property

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
    @AppStorage("selectedWeightingTypeStorage") private var selectedWeightingTypeStorage: String = WeightingType.none.rawValue

    var selectedWeightingType: WeightingType {
        get { WeightingType(rawValue: selectedWeightingTypeStorage) ?? .none }
        set { selectedWeightingTypeStorage = newValue.rawValue }
    }

    // MARK: - Computed Properties

    /// Provides the data points for the time-domain graph, switching between raw and weighted.
    var currentGraphTimeData: [IdentifiableGraphPoint] {
        var points: [IdentifiableGraphPoint] = []
        // Ensure consistent order of axes in the graph
        let sortedActiveAxes = activeAxes.sorted(by: { $0.rawValue < $1.rawValue })

        // Use the most reliable sample rate available
        let effectiveSampleRate = self.calculatedActualAverageSamplingRateForFFT ?? Double(self.actualCoreMotionRequestRate)

        switch displayTimeDataType {
        case .raw:
            for axis in sortedActiveAxes {
                if let seriesData = timeSeriesData[axis] { // timeSeriesData stores [DataPoint]
                    points.append(contentsOf: seriesData.map {
                        IdentifiableGraphPoint(axis: axis, xValue: $0.timestamp, yValue: $0.value)
                    })
                }
            }
        case .weighted:
            // Weighted data is only available after processing, and if sample rate is valid
            guard effectiveSampleRate > 0,
                  !weightedTimeSeriesX.isEmpty || !weightedTimeSeriesY.isEmpty || !weightedTimeSeriesZ.isEmpty else {
                // Fallback to raw data if weighted is not available (e.g. during/before recording)
                // or if conditions for generating it weren't met.
                for axis in sortedActiveAxes {
                    if let seriesData = timeSeriesData[axis] {
                        points.append(contentsOf: seriesData.map {
                            IdentifiableGraphPoint(axis: axis, xValue: $0.timestamp, yValue: $0.value)
                        })
                    }
                }
                // Optionally, could set a flag here to inform UI that weighted data was requested but unavailable.
                // Or, the UI picker for .weighted could be disabled if weighted data is not ready.
                // For now, this fallback ensures the graph doesn't go blank if .weighted is selected prematurely.
                return points
            }

            for axis in sortedActiveAxes {
                let dataSeries: [Double]
                switch axis {
                case .x: dataSeries = weightedTimeSeriesX
                case .y: dataSeries = weightedTimeSeriesY
                case .z: dataSeries = weightedTimeSeriesZ
                }

                points.append(contentsOf: dataSeries.enumerated().map { (index, value) -> IdentifiableGraphPoint in
                    let timestamp = Double(index) / effectiveSampleRate
                    return IdentifiableGraphPoint(axis: axis, xValue: timestamp, yValue: value)
                })
            }
        }
        return points
    }

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
        // selectedWeightingType is now a computed property backed by AppStorage, no manual init needed from stored rawValue here.
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
        self.weightedRmsX = 0.0; self.weightedRmsY = 0.0; self.weightedRmsZ = 0.0
        self.mtvvX = 0.0; self.mtvvY = 0.0; self.mtvvZ = 0.0
        self.vdvX = 0.0; self.vdvY = 0.0; self.vdvZ = 0.0; self.vdvTotal = 0.0
        Task { @MainActor in self.currentRoll = 0.0; self.currentPitch = 0.0 }
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
            Task { @MainActor in
                strongSelf.currentRoll = dataPayload.attitude.roll * 180.0 / .pi
                strongSelf.currentPitch = dataPayload.attitude.pitch * 180.0 / .pi
            }
        }
    }

    func stopLiveAttitudeMonitoring() {
        guard self.isLiveAttitudeMonitoringActive else { return }
        self.isLiveAttitudeMonitoringActive = false
        self.motionSessionForLiveAttitude.stopDeviceMotionUpdates(for: self)
        Task { @MainActor in
            self.currentRoll = 0.0
            self.currentPitch = 0.0
        }
    }

    // MARK: - Main Measurement Control
    @MainActor
    func startMeasurement() {
        guard self.measurementState == .idle else { return }
        self.resetDataForNewRecording()
        
        if self.recordingStartDelaySetting > 0 {
            self.measurementState = .preRecordingCountdown
            self.isRecording = false
            self.timeLeft = self.recordingStartDelaySetting
            self.preRecordingPhaseStartTime = Date()
            self.axisRanges.maxX = self.recordingStartDelaySetting
            
            self.preRecordingDelayTimer?.invalidate()
            self.preRecordingDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timerRef in
                Task { @MainActor in
                    guard let strongSelf = self, strongSelf.measurementState == .preRecordingCountdown else {
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
                        strongSelf.measurementState = .idle
                    }
                }
            }
        } else {
            self.beginActualRecording()
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
            Task { @MainActor in self?.captureNewSamples() }
        }
        
        self.durationCountdownTimer?.invalidate()
        let timerInterval = 0.05
        self.durationCountdownTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] tR in
            Task { @MainActor in
                guard let s = self,s.isRecording else{tR.invalidate();return}
                if let rST=s.recordingActualStartTime{s.elapsedTime=Date().timeIntervalSince(rST)}else{s.elapsedTime+=timerInterval}
                if s.autoStopRecordingEnabled && s.measurementDurationSetting > 0 { s.timeLeft=max(0,s.measurementDurationSetting-s.elapsedTime) }
                if s.measurementState == .recording{
                    let cmt=s.timeSeriesData[Axis.x]?.last?.timestamp ?? s.elapsedTime
                    if s.autoStopRecordingEnabled && s.measurementDurationSetting > 0 {
                        s.axisRanges.minX = 0; s.axisRanges.maxX = max(s.measurementDurationSetting, cmt + 0.2)
                    } else { let windowDur = 10.0; s.axisRanges.minX = max(0, s.elapsedTime - windowDur); s.axisRanges.maxX = s.elapsedTime + 0.2 }
                }
                if s.autoStopRecordingEnabled && s.measurementDurationSetting > 0 && s.elapsedTime >= s.measurementDurationSetting { s.stopMeasurement() }
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
            Task{@MainActor in self.captureNewSamples()}
        }
        self.isRecording=false
        self.measurementState = wasPreRecording ? .idle : .completed
        
        if !wasPreRecording{
            if let sT=self.recordingActualStartTime{self.elapsedTime=Date().timeIntervalSince(sT)}
            if self.autoStopRecordingEnabled && self.measurementDurationSetting > 0 {self.timeLeft=max(0,self.measurementDurationSetting-self.elapsedTime)} else {self.timeLeft=0}
            let fMT=Axis.allCases.compactMap{self.timeSeriesData[$0]?.last?.timestamp}.max() ?? self.elapsedTime
            self.axisRanges.minX = 0
            self.axisRanges.maxX=max(fMT,self.currentEffectiveMaxGraphDuration)

            // Calculate Unweighted RMS
            if self.collectedSamplesCount > 0 {
                self.rmsX = self.calculateOverallRMS(for: .x, weighted: false)
                self.rmsY = self.calculateOverallRMS(for: .y, weighted: false)
                self.rmsZ = self.calculateOverallRMS(for: .z, weighted: false)

                // Calculate Weighted RMS (placeholder logic)
                self.weightedRmsX = self.calculateOverallRMS(for: .x, weighted: true)
                self.weightedRmsY = self.calculateOverallRMS(for: .y, weighted: true)
                self.weightedRmsZ = self.calculateOverallRMS(for: .z, weighted: true)

                // --- Placeholder for MTVV Calculation ---
                // MTVV should be calculated from the time-domain frequency-weighted acceleration data.
                // This involves calculating running RMS values over short intervals (e.g., 1s) and finding the maximum.
                // For now, setting to 0.0 as a placeholder.
                // if self.selectedWeightingType != .none {
                //     // let weightedXDataForMTVV = FrequencyWeightingFilter.applyWeightingFilter(data: self.timeSeriesData[Axis.x]?.map{$0.value} ?? [], sampleRate: self.calculatedActualAverageSamplingRateForFFT ?? 0, weightingType: self.selectedWeightingType)
                //     // self.mtvvX = calculateMTVV(data: weightedXDataForMTVV, sampleRate: self.calculatedActualAverageSamplingRateForFFT ?? 0) // Future function
                //     // Similarly for Y and Z, applying appropriate weighting (e.g. Wd for X/Y, Wk or Wb for Z)
                //     print("MTVV calculation placeholder for \(self.selectedWeightingType.rawValue) data (IMPLEMENTATION PENDING)")
                // } else {
                //     // Potentially calculate MTVV on unweighted data or set to 0 / indicate N/A
                //     print("MTVV for unweighted data - placeholder or N/A")
                // }
                // self.mtvvX = 0.0 // Placeholder
                // self.mtvvY = 0.0 // Placeholder
                // self.mtvvZ = 0.0 // Placeholder

                // Actual MTVV Calculation
                let mtvvWindowSeconds = 1.0 // As per ISO 2631-1 for MTVV
                if self.selectedWeightingType != .none && sampleRate > 0 {
                    // MTVV is typically calculated on weighted data.
                    self.mtvvX = DynaVibe.calculateMTVV(
                        weightedTimeSeries: self.weightedTimeSeriesX,
                        sampleRate: sampleRate,
                        windowSeconds: mtvvWindowSeconds
                    )
                    self.mtvvY = DynaVibe.calculateMTVV(
                        weightedTimeSeries: self.weightedTimeSeriesY,
                        sampleRate: sampleRate,
                        windowSeconds: mtvvWindowSeconds
                    )
                    self.mtvvZ = DynaVibe.calculateMTVV(
                        weightedTimeSeries: self.weightedTimeSeriesZ,
                        sampleRate: sampleRate,
                        windowSeconds: mtvvWindowSeconds
                    )
                    // print("MTVV Calculated: X=\(self.mtvvX), Y=\(self.mtvvY), Z=\(self.mtvvZ)")
                } else {
                    // If no weighting or no valid sample rate, reset MTVV values
                    self.mtvvX = 0.0
                    self.mtvvY = 0.0
                    self.mtvvZ = 0.0
                }

                // Actual VDV Calculation
                // sampleRate is already defined in this scope from the MTVV calculation section or should be.
                // Let's ensure it is, or re-fetch if necessary for clarity.
                let effectiveSampleRate = self.calculatedActualAverageSamplingRateForFFT ?? Double(self.actualCoreMotionRequestRate)

                if self.selectedWeightingType != .none && effectiveSampleRate > 0 {
                    // VDV is typically calculated on weighted data.
                    // If .none is selected, weightedTimeSeries would be same as raw if applyWeightingViaFFT handles it that way.
                    self.vdvX = calculateVDV( // Calling the global function from FrequencyWeighting.swift
                        weightedTimeSeries: self.weightedTimeSeriesX,
                        sampleRate: effectiveSampleRate
                    )
                    self.vdvY = calculateVDV(
                        weightedTimeSeries: self.weightedTimeSeriesY,
                        sampleRate: effectiveSampleRate
                    )
                    self.vdvZ = calculateVDV(
                        weightedTimeSeries: self.weightedTimeSeriesZ,
                        sampleRate: effectiveSampleRate
                    )

                    // Calculate vdvTotal = (vdvX^4 + vdvY^4 + vdvZ^4)^(1/4)
                    let sumOfVDVFourthPowers = pow(self.vdvX, 4) + pow(self.vdvY, 4) + pow(self.vdvZ, 4)
                    self.vdvTotal = pow(sumOfVDVFourthPowers, 0.25)

                } else {
                    // If no weighting or no valid sample rate, reset VDV values
                    self.vdvX = 0.0
                    self.vdvY = 0.0
                    self.vdvZ = 0.0
                    self.vdvTotal = 0.0
                }

            } else {
                self.resetRMSValuesAndAttitude() // Resets both weighted and unweighted, and now MTVV/VDV
            }

            self.calculateActualAverageRate()
            if self.collectedSamplesCount>0{self.computeFFT()}else{self.isFFTReady=false;self.calculatedActualAverageSamplingRateForFFT=nil}
        } else{
            self.updateIdleStateDisplayValues()
        }
        self.recordingActualStartTime=nil
        self.preRecordingPhaseStartTime=nil
        if self.useLinearAccelerationSetting {
            self.startLiveAttitudeMonitoring()
        }
    }

    @MainActor
    func resetMeasurement() {
        if self.isRecording||self.measurementState == .preRecordingCountdown{self.stopMeasurement()};
        self.resetDataForNewRecording()
        self.measurementState = .idle; self.isFFTReady=false; self.elapsedTime=0
        self.updateIdleStateDisplayValues()
        self.latestX=0; self.latestY=0; self.latestZ=0; self.calculatedActualAverageSamplingRateForFFT=nil; self.currentRoll=0; self.currentPitch=0
        self.recordingActualStartTime=nil; self.preRecordingPhaseStartTime=nil
        if self.useLinearAccelerationSetting { self.startLiveAttitudeMonitoring() }
        else { self.stopLiveAttitudeMonitoring() }
    }

    @MainActor
    func resetDataForNewRecording() {
        Axis.allCases.forEach{a in self.timeSeriesData[a]?.removeAll(); self.fftMagnitudes[a]?.removeAll()}
        self.fftFrequencies.removeAll(); self.lastProcessedSampleTimestamp=0
        self.weightedTimeSeriesX.removeAll()
        self.weightedTimeSeriesY.removeAll()
        self.weightedTimeSeriesZ.removeAll()
        self.resetRMSValuesAndAttitude() // Resets RMS, weightedRMS, MTVV, VDV
    }

    // Calculates RMS. If 'weighted' is true, it uses the pre-calculated weighted time series.
    // Otherwise, it uses the raw time series data.
    private func calculateOverallRMS(for axis: Axis, weighted: Bool) -> Double {
        let dataSeries: [Double]

        if weighted {
            // Use the time series data that has already been weighted via FFT-IFFT method.
            // Note: If selectedWeightingType was .none, applyWeightingViaFFT would have
            // returned the original unweighted series, so this branch correctly handles that too
            // by calculating RMS on what is effectively unweighted data in that specific scenario.
            switch axis {
            case .x:
                dataSeries = self.weightedTimeSeriesX
            case .y:
                dataSeries = self.weightedTimeSeriesY
            case .z:
                dataSeries = self.weightedTimeSeriesZ
            }
        } else {
            // Use the raw (or gravity-compensated if useLinearAccelerationSetting is true) time series data.
            guard let rawDataPoints = self.timeSeriesData[axis] else { return 0.0 }
            dataSeries = rawDataPoints.map { $0.value }
        }

        guard !dataSeries.isEmpty else { return 0.0 }

        let sumOfSquares = dataSeries.reduce(0.0) { $0 + ($1 * $1) }
        return sqrt(sumOfSquares / Double(dataSeries.count))
    }
    
    @MainActor
    func captureNewSamples() {
        guard self.measurementState == .recording || (self.measurementState == .completed && self.dataFetchTimer == nil && !self.isRecording) else {return}
        let aRD=self.recorder.getRecordedData(); let nS=aRD.filter{$0.timestamp > self.lastProcessedSampleTimestamp}; guard !nS.isEmpty else {return}
        var cMAY=abs(self.axisRanges.maxY)

        // Placeholder for where frequency weighting might be applied if done on-the-fly
        // or before appending to timeSeriesData.
        // For now, timeSeriesData stores raw (or gravity-compensated) data.
        // Weighting for analysis (RMS, FFT) would ideally be applied to a copy of this data
        // after recording is complete, or if live weighted FFT is needed, then on chunks.

        for s in nS{
            self.timeSeriesData[Axis.x]?.append(.init(timestamp:s.timestamp,value:s.x))
            self.timeSeriesData[Axis.y]?.append(.init(timestamp:s.timestamp,value:s.y))
            self.timeSeriesData[Axis.z]?.append(.init(timestamp:s.timestamp,value:s.z))
            cMAY=max(cMAY,abs(s.x),abs(s.y),abs(s.z))
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
        // TODO: Apply frequency weighting to data before RMS if selectedWeightingType != .none
        // This would involve creating a weighted copy of dPs.map{$0.value}
        // using the FrequencyWeightingFilter (once implemented for time-domain)
        // or by weighting the FFT spectrum and then calculating RMS from weighted spectrum (Parseval's theorem).
        // For now, calculating RMS on unweighted (or gravity-compensated) data.
        // if selectedWeightingType != .none {
        //     print("RMS calculation for \(axis) would use \(selectedWeightingType.rawValue) - (FILTER IMPLEMENTATION PENDING)")
        // }
        // This logic moved into the updated calculateOverallRMS(for:weighted:) function
        // guard let dPs=self.timeSeriesData[axis],!dPs.isEmpty else{return 0.0}
        // let v=dPs.map{$0.value};let sOS=v.reduce(0.0){$0+($1*$1)};return sqrt(sOS/Double(v.count))
        // The old function signature and body are removed by the replace above.
        // This search block is targeting the old function to replace it.
        // However, the previous replace block for calculateOverallRMS should be adjusted.
        // Let's assume the previous SEARCH block for calculateOverallRMS was meant to be replaced entirely
        // by the new calculateOverallRMS(for:weighted:)
        // For this specific search block, it's now part of the new function.
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
    func computeFFT() {
        guard self.collectedSamplesCount > 0, let rateForFFT = self.calculatedActualAverageSamplingRateForFFT else {self.isFFTReady = false; return}
        self.isFFTReady = false

        // TODO: Apply frequency weighting here if selectedWeightingType != .none before FFT
        // This could be done by:
        // 1. Applying a time-domain filter (from FrequencyWeightingFilter) to copies of xV, yV, zV.
        // 2. Or, by multiplying the resulting FFT magnitudes by getFrequencyWeightingFactor().
        // Method 2 is simpler for now as time-domain filter is not ready.

        // if selectedWeightingType != .none {
        //     print("FFT computation would use \(selectedWeightingType.rawValue) weighting - (FILTER APPLICATION PENDING)")
        // }

        let xV = (self.timeSeriesData[Axis.x] ?? []).map{$0.value}
        let yV = (self.timeSeriesData[Axis.y] ?? []).map{$0.value}
        let zV = (self.timeSeriesData[Axis.z] ?? []).map{$0.value}

        let analyzer = self.fftAnalyzer
        Task.detached(priority: .userInitiated) { [weak self, analyzer] in
            guard let strongSelf = self else { return }
            var rX = analyzer.performFFT(input:xV, samplingRate:rateForFFT)
            var rY = analyzer.performFFT(input:yV, samplingRate:rateForFFT)
            var rZ = analyzer.performFFT(input:zV, samplingRate:rateForFFT)

            // The requirement is to display the RAW, UNWEIGHTED spectrum.
            // Therefore, the application of getFrequencyWeightingFactor to the display spectrum is removed.
            // If a weighted spectrum view is needed later, it would be a separate feature/property.
            // if strongSelf.selectedWeightingType != .none {
            //     print("Applying \(strongSelf.selectedWeightingType.rawValue) to FFT Magnitudes FOR DISPLAY - THIS IS NOW REMOVED")
            //     for i in 0..<rX.frequencies.count {
            //         let factor = getFrequencyWeightingFactor(frequency: rX.frequencies[i], type: strongSelf.selectedWeightingType)
            //         if !rX.magnitude.isEmpty { rX.magnitude[i] *= factor }
            //         if !rY.magnitude.isEmpty { rY.magnitude[i] *= factor }
            //         if !rZ.magnitude.isEmpty { rZ.magnitude[i] *= factor }
            //     }
            // }

            await MainActor.run {
                strongSelf.fftFrequencies=rX.frequencies
                strongSelf.fftMagnitudes[Axis.x]=rX.magnitude
                strongSelf.fftMagnitudes[Axis.y]=rY.magnitude
                strongSelf.fftMagnitudes[Axis.z]=rZ.magnitude
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

        let xSamples = self.timeSeriesData[Axis.x] ?? []
        let ySamples = self.timeSeriesData[Axis.y] ?? []
        let zSamples = self.timeSeriesData[Axis.z] ?? []
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

