// UI/MultiLineGraphView.swift
import SwiftUI
import Charts

// Assume IdentifiableGraphPoint is defined (e.g., in Models/) and accessible
// Assume Axis enum is defined (e.g., in Shared/) and accessible, and is Hashable

struct MultiLineGraphView: View {

    struct AxisRanges: Equatable {
        var minY: Double
        var maxY: Double
        var minX: Double
        var maxX: Double
    }

    let plotData: [IdentifiableGraphPoint]
    let ranges: AxisRanges
    let isFrequencyDomain: Bool
    let axisColors: [Axis: Color]
    let yAxisLabelUnit: String // New property for Y-axis unit

    @State private var selectedX: Double? = nil
    @State private var selectedPlotPoints: [IdentifiableGraphPoint] = []
    @State private var showCursorInfo: Bool = false // Controls visibility of the overlay

    var body: some View {
        ChartReader { chartProxyInReaderSIEGFRIEDLUND_MARKER_TAG_WORKER_PROVIDED_CODE_WILL_BE_INSERTED_HERE
            let configuredChart = Chart {
                ForEach(plotData) { point in
                    LineMark(
                        x: .value(isFrequencyDomain ? "Frequency" : "Time", point.xValue),
                        y: .value(isFrequencyDomain ? "Magnitude" : "Value", point.yValue)
                    )
                    .foregroundStyle(by: .value("Axis", point.axis.rawValue))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                if let selectedX = selectedX, showCursorInfo {
                    RuleMark(x: .value("SelectedX", selectedX))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading, spacing: 4) {
                             Text(isFrequencyDomain ? String(format: "%.1f Hz", selectedX) : String(format: "%.2f s", selectedX))
                                .font(.caption)
                                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                .background(Capsule().fill(Material.thinMaterial))
                                .foregroundColor(.primary)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                }

                ForEach(selectedPlotPoints.filter { _ in showCursorInfo }) { point in
                     PointMark(
                         x: .value(isFrequencyDomain ? "Frequency" : "Time", point.xValue),
                         y: .value(isFrequencyDomain ? "Magnitude" : "Value", point.yValue)
                     )
                     .foregroundStyle(axisColors[point.axis] ?? .gray)
                     .symbolSize(50)
                     .annotation(position: .overlay, alignment: .center, spacing: 0) {
                         Text(String(format: "%.2f", point.yValue))
                             .font(.caption2)
                             .padding(2)
                             .background(Color.black.opacity(0.5))
                             .foregroundColor(.white)
                             .clipShape(Capsule())
                     }
                 }
            }
            .chartForegroundStyleScale(
                domain: Axis.allCases.map { $0.rawValue },
                range: Axis.allCases.map { axisColors[$0] ?? .gray }
            )
            .chartXScale(domain: ranges.minX ... max(ranges.minX + (isFrequencyDomain ? 0.1 : 0.01), ranges.maxX))
            .chartYScale(domain: ranges.minY ... ranges.maxY)
            .chartXAxisLabel(isFrequencyDomain ? "Frequency (Hz)" : "Time (s)", alignment: .center)
            // Updated Y-Axis Label to use yAxisLabelUnit
            .chartYAxisLabel(isFrequencyDomain ? "Magnitude" : "Acceleration (\(yAxisLabelUnit))", alignment: .centerLastTextBaseline)
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

            configuredChart
                .chartBackground { chartProxyForGesture in
                    GeometryReader { geometryProxy in
                        Rectangle().fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let location = value.location
                                        let rawXDataValue: Double? = chartProxyForGesture.value(atX: location.x, as: Double.self)

                                        if let currentRawX = rawXDataValue {
                                            if let (snappedX, pointsAtX) = snapToClosestDataX(
                                                targetX: currentRawX,
                                                inData: plotData,
                                                chartProxy: chartProxyForGesture,
                                                geometryProxy: geometryProxy
                                            ) {
                                                self.selectedX = snappedX
                                                self.selectedPlotPoints = pointsAtX
                                                self.showCursorInfo = true
                                            } else {
                                                self.selectedX = currentRawX
                                                self.selectedPlotPoints = []
                                                self.showCursorInfo = true
                                            }
                                        } else {
                                            self.selectedX = nil
                                            self.selectedPlotPoints = []
                                            self.showCursorInfo = false
                                        }
                                    }
                                    .onEnded { _ in
                                        // To keep selection:
                                        // self.showCursorInfo = (self.selectedX != nil && !self.selectedPlotPoints.isEmpty)
                                        // Or to clear selection after drag:
                                        // self.selectedX = nil
                                        // self.selectedPlotPoints = []
                                        // self.showCursorInfo = false
                                    }
                            )
                    }
                }
        }
    }

    private func snapToClosestDataX(targetX: Double?,
                                   inData: [IdentifiableGraphPoint],
                                   chartProxy: ChartProxy,
                                   geometryProxy: GeometryProxy) -> (snappedX: Double, pointsAtX: [IdentifiableGraphPoint])? {

        guard let currentTargetX = targetX, !inData.isEmpty else { return nil }

        let plotAreaFrame = geometryProxy.frame(in: .local)

        let uniqueXValuesInView = Array(Set(inData.compactMap { dataPoint -> Double? in
            guard let screenX = chartProxy.position(forX: dataPoint.xValue) else { return nil }
            return (screenX >= 0 && screenX <= plotAreaFrame.width) ? dataPoint.xValue : nil
        })).sorted()

        guard !uniqueXValuesInView.isEmpty else { return nil }

        var finalSnappedX: Double = uniqueXValuesInView[0]
        var minDistance: CGFloat = .infinity

        guard let targetScreenX = chartProxy.position(forX: currentTargetX) else {
             return nil
        }

        for xData in uniqueXValuesInView {
            guard let currentDataScreenX = chartProxy.position(forX: xData) else { continue }
            let distance = abs(currentDataScreenX - targetScreenX)
            if distance < minDistance {
                minDistance = distance
                finalSnappedX = xData
            }
        }

        let pointsAtSnappedX = inData.filter { $0.xValue == finalSnappedX }

        if !pointsAtSnappedX.isEmpty {
            return (finalSnappedX, pointsAtSnappedX)
        }

        return nil
    }
}

// --- Preview Setup ---
private struct MultiLineGraphView_PreviewHelper {
    static func generatePreviewSeries(axis: Axis, count: Int, scale: Double, offset: Double = 0) -> [IdentifiableGraphPoint] {
        (0..<count).map { index -> IdentifiableGraphPoint in
            let time = Double(index) / 50.0
            let value = sin((time + offset) * 2 * .pi) * scale + Double.random(in: -0.1...0.1)
            return IdentifiableGraphPoint(axis: axis, xValue: time, yValue: value)
        }
    }

    static func makePlotData() -> [IdentifiableGraphPoint] {
        let xSeries = generatePreviewSeries(axis: .x, count: 100, scale: 1.0)
        let ySeries = generatePreviewSeries(axis: .y, count: 100, scale: 0.7, offset: 0.5)
        let zSeries = generatePreviewSeries(axis: .z, count: 100, scale: 0.4, offset: 1.0)
        return xSeries + ySeries + zSeries
    }

    static func makeRanges(fromPlotData data: [IdentifiableGraphPoint]) -> MultiLineGraphView.AxisRanges {
        let minX = data.min(by: { $0.xValue < $1.xValue })?.xValue ?? 0
        let maxX = data.max(by: { $0.xValue < $1.xValue })?.xValue ?? 2.0
        return MultiLineGraphView.AxisRanges(minY: -1.5, maxY: 1.5, minX: minX, maxX: maxX)
    }
    
    static let previewPlotData = makePlotData()
    static let previewRanges = makeRanges(fromPlotData: previewPlotData)
    static let previewAxisColors: [Axis: Color] = [Axis.x: .red, Axis.y: .green, Axis.z: .blue]
    static let previewYAxisUnit: String = "m/s²" // Added for preview
}

#Preview("Time Domain Graph with Cursor") {
    MultiLineGraphView(
        plotData: MultiLineGraphView_PreviewHelper.previewPlotData,
        ranges: MultiLineGraphView_PreviewHelper.previewRanges,
        isFrequencyDomain: false,
        axisColors: MultiLineGraphView_PreviewHelper.previewAxisColors,
        yAxisLabelUnit: MultiLineGraphView_PreviewHelper.previewYAxisUnit // Added for preview
    )
    .padding()
    .frame(height: 240)
}

#Preview("Frequency Domain Graph (Empty)") {
    MultiLineGraphView(
        plotData: [],
        ranges: MultiLineGraphView.AxisRanges(minY: 0, maxY: 1, minX: 0, maxX: 50),
        isFrequencyDomain: true,
        axisColors: MultiLineGraphView_PreviewHelper.previewAxisColors,
        yAxisLabelUnit: "g" // Example with 'g'
    )
    .padding()
    .frame(height: 240)
    .overlay(Text("No Frequency Data").opacity(0.5))
}
// Dummy definitions for tool understanding, assuming they exist in the project
 public enum Axis: String, CaseIterable, Identifiable { case x,y,z; public var id: String { rawValue }}
 public struct IdentifiableGraphPoint: Identifiable { public var id = UUID(); public var axis: Axis; public var xValue: Double; public var yValue: Double }
```
