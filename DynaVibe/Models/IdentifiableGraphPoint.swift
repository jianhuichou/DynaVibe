import Foundation
// Import AxisAndLegend.swift to make Axis visible
// This works if AxisAndLegend.swift is in the same target and module
// If not, ensure AxisAndLegend.swift is added to the Compile Sources in Xcode

// Explicitly import AxisAndLegend.swift for Axis enum
// typealias Axis = DynaVibe.Axis

// This struct will be used by MultiLineGraphView
public struct IdentifiableGraphPoint: Identifiable, Equatable {
    public let id = UUID()
    public let axis: Axis // The axis this point belongs to (X, Y, or Z)
    public let xValue: Double // Represents Time or Frequency
    public let yValue: Double // Represents Acceleration or Magnitude

    public init(axis: Axis, xValue: Double, yValue: Double) {
        self.axis = axis
        self.xValue = xValue
        self.yValue = yValue
    }

    public static func == (lhs: IdentifiableGraphPoint, rhs: IdentifiableGraphPoint) -> Bool {
        lhs.axis == rhs.axis && lhs.xValue == rhs.xValue && lhs.yValue == rhs.yValue
    }
}
