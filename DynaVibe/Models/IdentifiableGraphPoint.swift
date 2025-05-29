// In Models/IdentifiableGraphPoint.swift (or alongside DataPoint.swift)
import Foundation

// This struct will be used by MultiLineGraphView
public struct IdentifiableGraphPoint: Identifiable {
    public let id = UUID()
    public let axis: Axis // The axis this point belongs to (X, Y, or Z)
    public let xValue: Double // Represents Time or Frequency
    public let yValue: Double // Represents Acceleration or Magnitude

    public init(axis: Axis, xValue: Double, yValue: Double) {
        self.axis = axis
        self.xValue = xValue
        self.yValue = yValue
    }
}
