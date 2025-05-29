// Extracted from phyphox-iOS
// Enum for available sensor types

import Foundation

enum SensorType: String, Equatable, CaseIterable {
    case accelerometer
    case gyroscope
    case linearAcceleration = "linear_acceleration"
    case magneticField = "magnetic_field"
    case pressure
    case light
    case proximity
    case temperature
    case humidity
    case attitude
    case gravity
}

extension SensorType {
    var localizedName: String {
        switch self {
        case .accelerometer: return "Accelerometer"
        case .gyroscope: return "Gyroscope"
        case .humidity: return "Humidity"
        case .light: return "Light"
        case .linearAcceleration: return "Linear Acceleration"
        case .magneticField: return "Magnetic Field"
        case .pressure: return "Pressure"
        case .proximity: return "Proximity"
        case .temperature: return "Temperature"
        case .attitude: return "Attitude"
        case .gravity: return "Gravity"
        }
    }
}
