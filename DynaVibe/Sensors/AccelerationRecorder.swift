// Sensors/AccelerationRecorder.swift
import Foundation
import CoreMotion

class AccelerationRecorder: MotionSessionReceiver {
    private let motionSession = MotionSession.current()
    private var isRecordingActive = false // For data storage
    private var isLiveAttitudeActive = false // For live attitude updates

    private var currentRecordingData: [(timestamp: TimeInterval, x: Double, y: Double, z: Double, attitude: CMAttitude?)] = []
    private var recordingStartTime: TimeInterval?
    
    var useDeviceMotionForData: Bool = true // Set by ViewModel for full recording mode

    // Callback for live attitude updates
    public var attitudeUpdateHandler: ((CMAttitude) -> Void)?

    // --- Methods for Full Data Recording ---
    func startRecording() {
        guard motionSession.isMotionHardwareAvailable else {
            print("⚠️ Motion sensors are not available."); return
        }
        guard !isRecordingActive else {
            print("AccelerationRecorder: Already recording data."); return
        }
        
        isRecordingActive = true
        currentRecordingData.removeAll() // Clear buffer for new recording session
        recordingStartTime = ProcessInfo.processInfo.systemUptime
        
        // Ensure device motion is started if useDeviceMotionForData is true
        // This will also trigger attitude updates via the shared callback
        if useDeviceMotionForData {
            startDeviceMotionSensorUpdates() // Ensures sensor is on
        } else {
            startRawAccelerometerSensorUpdates() // Ensures sensor is on
        }
    }
    
    func stopRecording() {
        guard isRecordingActive else { return }
        isRecordingActive = false
        // Don't stop sensors if only live attitude is desired and was active before.
        // The ViewModel will manage stopping live attitude updates separately.
        // If live attitude is NOT active, then we can stop the sensors.
        if !isLiveAttitudeActive {
            motionSession.stopAllUpdates(for: self)
        }
    }

    // --- Methods for Live Attitude Updates ---
    func startLiveAttitudeUpdates() {
        guard motionSession.isDeviceMotionAvailable else {
            print("⚠️ Device Motion (for attitude) not available."); return
        }
        if !isLiveAttitudeActive && !motionSession.deviceMotionRunning { // Only start if not already running for this recorder
            isLiveAttitudeActive = true
            startDeviceMotionSensorUpdates(forAttitudeOnly: true)
        } else if motionSession.deviceMotionRunning {
             isLiveAttitudeActive = true // Mark as active even if sensor was already on (e.g. during recording)
        }
    }

    func stopLiveAttitudeUpdates() {
        guard isLiveAttitudeActive else { return }
        isLiveAttitudeActive = false
        // Only stop device motion if we are NOT in an active data recording session that needs it
        if !isRecordingActive || (isRecordingActive && !useDeviceMotionForData) {
            motionSession.stopDeviceMotionUpdates(for: self)
        }
    }

    // --- Internal Sensor Start Methods ---
    private func startDeviceMotionSensorUpdates(forAttitudeOnly: Bool = false) {
        let effectiveInterval = 1.0 / Double(motionSession.samplingRate)
        _ = motionSession.startDeviceMotionUpdates(for: self, interval: effectiveInterval) { [weak self] (payload, error) in
            guard let self = self else { return }
            if let err = error { print("Device Motion Error: \(err.localizedDescription)"); return }
            guard let dataPayload = payload else { return }

            // Always provide live attitude if handler is set and attitude available
            self.attitudeUpdateHandler?(dataPayload.attitude)

            // Only store data if a full recording is active
            if self.isRecordingActive && self.useDeviceMotionForData { // Ensure we are in correct recording mode
                let absoluteTime = ProcessInfo.processInfo.systemUptime
                let relativeTime = absoluteTime - (self.recordingStartTime ?? absoluteTime)
                self.currentRecordingData.append((
                    timestamp: relativeTime,
                    x: dataPayload.acceleration.x, y: dataPayload.acceleration.y, z: dataPayload.acceleration.z,
                    attitude: dataPayload.attitude
                ))
            }
        }
    }

    private func startRawAccelerometerSensorUpdates() {
        let effectiveInterval = 1.0 / Double(motionSession.samplingRate)
        _ = motionSession.startRawAccelerometerUpdates(for: self, interval: effectiveInterval) { [weak self] (accelData, error) in
            guard let self = self, self.isRecordingActive else { return } // Only store if recording
            if let err = error { print("Raw Accelerometer Error: \(err.localizedDescription)"); return }
            guard let accel = accelData else { return }
            
            let absoluteTime = ProcessInfo.processInfo.systemUptime
            let relativeTime = absoluteTime - (self.recordingStartTime ?? absoluteTime)
            self.currentRecordingData.append((
                timestamp: relativeTime,
                x: accel.acceleration.x * 9.80665, y: accel.acceleration.y * 9.80665, z: accel.acceleration.z * 9.80665,
                attitude: nil
            ))
        }
    }
    
    // --- Data Access and Configuration ---
    func getRecordedData() -> [(timestamp: TimeInterval, x: Double, y: Double, z: Double, attitude: CMAttitude?)] {
        return currentRecordingData
    }
    
    func clear() {
        currentRecordingData.removeAll(); recordingStartTime = nil
    }
    
    var motionSessionPublic: MotionSession { return motionSession }
    var isHardwareAvailable: Bool { return motionSession.isMotionHardwareAvailable }
    var isCurrentlyRecordingData: Bool { return isRecordingActive } // Renamed for clarity
}
