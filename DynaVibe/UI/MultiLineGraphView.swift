// UI/MultiLineGraphView.swift
import SwiftUI
import Charts

// Assume IdentifiableGraphPoint is defined (e.g., in Models/) and accessible
// Assume Axis enum is defined (e.g., in Shared/) and accessible, and is Hashable

struct MultiLineGraphView: View {

    struct AxisRanges: Equatable { // This nested struct remains the same
        var minY: Double
        var maxY: Double
        var minX: Double
        var maxX: Double
    }

    let plotData: [IdentifiableGraphPoint] // CHANGED: Now a single array of points
    let ranges: AxisRanges
    let isFrequencyDomain: Bool
    let axisColors: [Axis: Color] // Passed in to define the color scale

    var body: some View {
        Chart(plotData) { point in // Iterate over the plotData directly
            LineMark(
                x: .value(isFrequencyDomain ? "Frequency" : "Time", point.xValue),
                y: .value(isFrequencyDomain ? "Magnitude" : "Value", point.yValue)
            )
            // Use .foregroundStyle(by:) to group and color by axis
            .foregroundStyle(by: .value("Axis", point.axis.rawValue))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        // Define how rawValue strings map to actual Colors
        .chartForegroundStyleScale(
            domain: Axis.allCases.map { $0.rawValue }, // e.g., ["x", "y", "z"]
            range: Axis.allCases.map { axisColors[$0] ?? .gray } // e.g., [.red, .green, .blue]
        )
        // Chart-level modifiers remain similar
        .chartXScale(domain: ranges.minX ... max(ranges.minX + (isFrequencyDomain ? 0.1 : 0.01), ranges.maxX))
        .chartYScale(domain: ranges.minY ... ranges.maxY)
        .chartXAxisLabel(isFrequencyDomain ? "Frequency (Hz)" : "Time (s)", alignment: .center)
        .chartYAxisLabel(isFrequencyDomain ? "Magnitude (m/s²)" : "Acceleration (m/s²)", alignment: .centerLastTextBaseline)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: ranges.maxX - ranges.minX > 2 ? 6 : 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2,3]))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.fractionLength( (ranges.maxX - ranges.minX) < 10 && ranges.maxX != 0 && !isFrequencyDomain ? 1:0)))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2,3]))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// --- Preview Setup ---
// This needs to be updated to provide the new `plotData` structure
private struct MultiLineGraphView_PreviewHelper {
    static func generatePreviewSeries(axis: Axis, count: Int, scale: Double, offset: Double = 0) -> [IdentifiableGraphPoint] {
        (0..<count).map { index -> IdentifiableGraphPoint in
            let time = Double(index) / 50.0
            let value = sin((time + offset) * 2 * .pi) * scale
            return IdentifiableGraphPoint(axis: axis, xValue: time, yValue: value)
        }
    }

    static func makePlotData() -> [IdentifiableGraphPoint] {
        let xSeries = generatePreviewSeries(axis: .x, count: 256, scale: 1.0)
        let ySeries = generatePreviewSeries(axis: .y, count: 256, scale: 0.7, offset: 0.5)
        let zSeries = generatePreviewSeries(axis: .z, count: 256, scale: 0.4, offset: 1.0)
        return xSeries + ySeries + zSeries // Combine into a single array
    }

    static func makeRanges(fromPlotData data: [IdentifiableGraphPoint]) -> MultiLineGraphView.AxisRanges {
        // Find min/max across all points for a sensible default range
        let minX = data.min(by: { $0.xValue < $1.xValue })?.xValue ?? 0
        let maxX = data.max(by: { $0.xValue < $1.xValue })?.xValue ?? 5.0
        return MultiLineGraphView.AxisRanges(minY: -1.2, maxY: 1.2, minX: minX, maxX: maxX)
    }
    
    static let previewPlotData = makePlotData()
    static let previewRanges = makeRanges(fromPlotData: previewPlotData)
    // These colors are used for the .chartForegroundStyleScale
    static let previewAxisColors: [Axis: Color] = [Axis.x: .red, Axis.y: .green, Axis.z: .blue]
}

#Preview("Time Domain Graph") {
    MultiLineGraphView(
        plotData: MultiLineGraphView_PreviewHelper.previewPlotData,
        ranges: MultiLineGraphView_PreviewHelper.previewRanges,
        isFrequencyDomain: false,
        axisColors: MultiLineGraphView_PreviewHelper.previewAxisColors
    )
    .padding()
    .frame(height: 240)
}

#Preview("Frequency Domain Graph (Empty)") {
    MultiLineGraphView(
        plotData: [], // Empty plot data
        ranges: MultiLineGraphView.AxisRanges(minY: 0, maxY: 1, minX: 0, maxX: 50),
        isFrequencyDomain: true,
        axisColors: MultiLineGraphView_PreviewHelper.previewAxisColors
    )
    .padding()
    .frame(height: 240)
    .overlay(Text("No Frequency Data").opacity(0.5))
}
