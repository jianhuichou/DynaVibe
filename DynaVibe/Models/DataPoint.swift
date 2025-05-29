// In Models/DataPoint.swift
import Foundation

public struct DataPoint: Equatable, Identifiable {
    public let id: UUID // 'id' is a let constant
    public let timestamp: Double
    public let value: Double

    // Corrected Initializer:
    // Provide a default value for 'id' directly in the parameter list.
    // If 'id' is not passed by the caller, the default UUID() will be used.
    // If 'id' IS passed by the caller, that value will be used.
    // This ensures 'self.id' is assigned only once.
    public init(id: UUID = UUID(), timestamp: Double, value: Double) {
        self.id = id // This is the single assignment to the constant 'id'
        self.timestamp = timestamp
        self.value = value
    }
}
