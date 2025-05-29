// Sensors/MotionSession.swift
import Foundation
import CoreMotion

// MotionSessionReceiver class - (internal access by default)
class MotionSessionReceiver: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    static func ==(lhs: MotionSessionReceiver, rhs: MotionSessionReceiver) -> Bool { return lhs === rhs }
}

// Data Structures for MotionSession Output (internal access by default)
struct ProcessedAccelerationData { let x: Double; let y: Double; let z: Double }
struct DeviceMotionUpdatePayload {
    let acceleration: ProcessedAccelerationData
    let attitude: CMAttitude
    let rotationRate: CMRotationRate?; let gravity: CMAcceleration?
}

final class MotionSession {
    private lazy var motionManager = CMMotionManager()
    private(set) var accelerometerRunning = false
    private(set) var deviceMotionRunning = false
    private var accelerometerReceivers: [MotionSessionReceiver: (_ data: CMAccelerometerData?, _ error: Error?) -> Void] = [:]
    private var deviceMotionReceivers: [MotionSessionReceiver: (_ data: DeviceMotionUpdatePayload?, _ error: Error?) -> Void] = [:]
    private let receiversLock = NSLock()
    
    var samplingRate: Int = 100 // Target rate for the *next* stream start
    var provideUserAccelerationFromDeviceMotion: Bool = true

    var isMotionHardwareAvailable: Bool { motionManager.isAccelerometerAvailable || motionManager.isDeviceMotionAvailable }

    private func makeSensorQueue() -> OperationQueue {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated
        return queue
    }

    private static let shared = MotionSession(); static func current() -> MotionSession { return shared }
    private init() {}

    // MARK: - Accelerometer (Raw)
    var isAccelerometerAvailable: Bool { motionManager.isAccelerometerAvailable }

    func startRawAccelerometerUpdates(
        for receiver: MotionSessionReceiver, interval: TimeInterval? = nil,
        handler: @escaping (_ data: CMAccelerometerData?, _ error: Error?) -> Void
    ) -> Bool {
        guard isMotionHardwareAvailable else { print("⚠️ Raw Accelerometer not available."); return false }
        
        let effectiveInterval = interval ?? (1.0 / Double(samplingRate))
        receiversLock.withLock { accelerometerReceivers[receiver] = handler }
        
        // If already active but interval differs, or if not active, (re)start.
        if motionManager.isAccelerometerActive && motionManager.accelerometerUpdateInterval != effectiveInterval {
            print("MotionSession: Raw Accelerometer active with different interval. Restarting for new interval: \(effectiveInterval)")
            motionManager.stopAccelerometerUpdates()
            accelerometerRunning = false // Mark as not running before restart
        }
        
        if !accelerometerRunning { // Start if not running (or just stopped to change interval)
            accelerometerRunning = true
            motionManager.accelerometerUpdateInterval = effectiveInterval
            print("MotionSession: Starting Raw Accelerometer with interval \(effectiveInterval) (Rate: \(1.0/effectiveInterval) Hz)")
            motionManager.startAccelerometerUpdates(to: makeSensorQueue()) { [weak self] (data, error) in
                self?.receiversLock.withLock {
                    self?.accelerometerReceivers.values.forEach { $0(data, error) }
                }
            }
        }
        return true
    }

    func stopRawAccelerometerUpdates(for receiver: MotionSessionReceiver) {
        receiversLock.withLock { accelerometerReceivers.removeValue(forKey: receiver) }
        if accelerometerReceivers.isEmpty && accelerometerRunning {
            accelerometerRunning = false
            motionManager.stopAccelerometerUpdates()
            print("MotionSession: Stopped raw accelerometer updates (no more receivers).")
        }
    }

    // MARK: - Device Motion
    var isDeviceMotionAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func startDeviceMotionUpdates(
        for receiver: MotionSessionReceiver, interval: TimeInterval? = nil,
        referenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical,
        handler: @escaping (_ data: DeviceMotionUpdatePayload?, _ error: Error?) -> Void
    ) -> Bool {
        guard isDeviceMotionAvailable else { print("⚠️ Device Motion not available."); return false }

        let effectiveInterval = interval ?? (1.0 / Double(samplingRate)) // Use current samplingRate of MotionSession
        receiversLock.withLock { deviceMotionReceivers[receiver] = handler }

        // --- KEY CHANGE: Restart if active with different interval ---
        if motionManager.isDeviceMotionActive && motionManager.deviceMotionUpdateInterval != effectiveInterval {
            print("MotionSession: Device Motion active with different interval. Restarting for new interval: \(effectiveInterval)")
            motionManager.stopDeviceMotionUpdates() // Stop current stream
            deviceMotionRunning = false // Mark as not running before restart
        }
        
        if !deviceMotionRunning { // Start if not running (or just stopped to change interval)
            deviceMotionRunning = true
            motionManager.deviceMotionUpdateInterval = effectiveInterval
            print("MotionSession: Starting Device Motion with interval \(effectiveInterval) (Rate: \(1.0/effectiveInterval) Hz)")
            motionManager.startDeviceMotionUpdates(using: referenceFrame, to: makeSensorQueue()) { [weak self] (motionData, error) in
                guard let self = self else { return }
                var payload: DeviceMotionUpdatePayload? = nil
                if let motion = motionData {
                    let userAccelG = motion.userAcceleration; let gravityG = motion.gravity
                    let processedAccelG: CMAcceleration
                    if self.provideUserAccelerationFromDeviceMotion { processedAccelG = userAccelG }
                    else { processedAccelG = CMAcceleration(x: userAccelG.x + gravityG.x, y: userAccelG.y + gravityG.y, z: userAccelG.z + gravityG.z) }
                    let accelerationMS2 = ProcessedAccelerationData(x: processedAccelG.x*9.80665, y: processedAccelG.y*9.80665, z: processedAccelG.z*9.80665)
                    payload = DeviceMotionUpdatePayload(acceleration: accelerationMS2, attitude: motion.attitude, rotationRate: motion.rotationRate, gravity: motion.gravity)
                }
                // Notify all current receivers for device motion
                self.receiversLock.withLock {
                    self.deviceMotionReceivers.values.forEach { $0(payload, error) }
                }
            }
        }
        return true
    }

    func stopDeviceMotionUpdates(for receiver: MotionSessionReceiver) {
        receiversLock.withLock { deviceMotionReceivers.removeValue(forKey: receiver) }
        if deviceMotionReceivers.isEmpty && deviceMotionRunning {
            deviceMotionRunning = false
            motionManager.stopDeviceMotionUpdates()
            print("MotionSession: Stopped device motion updates (no more receivers).")
        }
    }

    func stopAllUpdates(for receiver: MotionSessionReceiver) {
        stopRawAccelerometerUpdates(for: receiver); stopDeviceMotionUpdates(for: receiver)
    }
}

// NSLock extension - keep as is
extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }; return try body()
    }
}
