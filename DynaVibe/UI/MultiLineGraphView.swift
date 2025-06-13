// UI/MultiLineGraphView.swift
import SwiftUI
import Charts
import os

public struct MultiLineGraphView: View {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DynaVibe",
        category: "MultiLineGraphView"
    )

    public struct AxisRanges: Equatable {
        public var minY: Double, maxY: Double, minX: Double, maxX: Double
    }

    let plotData: [IdentifiableGraphPoint]
    let ranges: AxisRanges
    let isFrequencyDomain: Bool
    let axisColors: [Axis: Color]
    let yAxisLabelUnit: String
    let xTicks: [Double] // X axis tick values
    let yTicks: [Double] // Y axis tick values
    let xGridLines: [Double]? // X axis grid line values (optional)
    let yGridLines: [Double]? // Y axis grid line values (optional)
    
    @State private var selectedX: Double? = nil
    @State private var showCursorInfo: Bool = false
    @State private var isLoading: Bool = false
    @State private var chartXRange: ClosedRange<Double>? = nil // For zoom/pan
    @State private var dragStartRange: ClosedRange<Double>? = nil

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Chart {
                    // Draw the line using only the actual data points (no interpolation)
                    ForEach(plotData) { point in
                        LineMark(
                            x: .value(isFrequencyDomain ? "Frequency (Hz)" : "Time (s)", point.xValue),
                            y: .value(isFrequencyDomain ? "Magnitude" : "Value", point.yValue)
                        )
                        .foregroundStyle(by: .value("Axis", point.axis.rawValue.uppercased()))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    // Always draw a horizontal rule at y = 0 for time series
                    if !isFrequencyDomain {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4]))
                            .foregroundStyle(Color.gray.opacity(0.5))
                    }
                    // Use provided xGridLines/yGridLines for grid lines if available, else fall back to xTicks/yTicks
                    ForEach(xGridLines ?? xTicks, id: \ .self) { x in
                        RuleMark(x: .value("GridX", x))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                    }
                    ForEach(yGridLines ?? yTicks, id: \ .self) { y in
                        RuleMark(y: .value("GridY", y))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                    }
                }
                .chartForegroundStyleScale(
                    domain: Axis.allCases.map { $0.rawValue.uppercased() },
                    range: Axis.allCases.map { axisColors[$0] ?? .gray }
                )
                .chartXScale(domain: chartXRange ?? (ranges.minX ... ranges.maxX))
                .chartYScale(domain: ranges.minY ... ranges.maxY)
                .chartXAxisLabel(isFrequencyDomain ? "Frequency (Hz)" : "Time (s)", alignment: .center)
                .chartYAxisLabel(isFrequencyDomain ? "Magnitude (\(yAxisLabelUnit))" : "Acceleration (\(yAxisLabelUnit))", alignment: .center)
                .chartXAxis {
                    AxisMarks(values: xTicks)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yTicks)
                }
                .chartLegend(position: .top, alignment: .trailing)
                .chartOverlay { chartProxy in
                    overlayContent(chartProxy: chartProxy)
                }
                .onChange(of: plotData) { _, newData in
                    setDefaultCursorPosition(for: newData)
                }
                .gesture(zoomAndPanGesture())
                if isLoading {
                    ProgressView().scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.5))
                }
            }
        }
    }

    // --- Cursor Overlay ---
    @ViewBuilder
    private func overlayContent(chartProxy: ChartProxy) -> some View {
        GeometryReader { geometryProxy in
            Rectangle().fill(.clear)
                .contentShape(Rectangle())
                .overlay {
                    if let plotFrameAnchor = chartProxy.plotFrame {
                        if showCursorInfo, let selectedX = selectedX {
                            let plotFrame = geometryProxy[plotFrameAnchor]
                            let xPosition = chartProxy.position(forX: selectedX) ?? 0
                            ZStack(alignment: .topLeading) {
                                // Vertical Cursor Line drawn at the actual x value
                                Rectangle()
                                    .fill(Color.gray.opacity(0.8))
                                    .frame(width: 1, height: plotFrame.height)
                                    .offset(x: xPosition, y: plotFrame.minY)
                                // X-Value Annotation (Time or Frequency)
                                Text(isFrequencyDomain ? String(format: "%.3f Hz", selectedX) : String(format: "%.4f s", selectedX))
                                    .font(.caption)
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 6)
                                    .background(Capsule().fill(Material.thin))
                                    .foregroundColor(.primary)
                                    .shadow(color: .black.opacity(0.1), radius: 2)
                                    .offset(x: xPosition + 4, y: plotFrame.minY)
                                // For each axis, show the curve point at the snapped x-value
                                ForEach(Axis.allCases, id: \.self) { axis in
                                    if let yValue = yValueForAxisAtX(axis: axis, x: selectedX) {
                                        let yPosition = chartProxy.position(forY: yValue) ?? 0
                                        Circle()
                                            .frame(width: 8, height: 8)
                                            .foregroundStyle(axisColors[axis] ?? .gray)
                                            .position(x: xPosition, y: yPosition)
                                        Text(String(format: "%.4f \(isFrequencyDomain ? "" : yAxisLabelUnit)", yValue))
                                            .font(.caption2)
                                            .padding(3)
                                            .background(Color.black.opacity(0.6))
                                            .foregroundColor(.white)
                                            .clipShape(Capsule())
                                            .position(x: xPosition, y: yPosition + (yValue > (ranges.minY + ranges.maxY) / 2 ? 15 : -15))
                                    }
                                }
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if let newX = snapToNearestTickX(at: value.location, chartProxy: chartProxy) {
                                setCursor(to: newX)
                            }
                        }
                        .onEnded { value in
                            if snapToNearestTickX(at: value.location, chartProxy: chartProxy) == nil {
                                clearCursor()
                            }
                        }
                )
        }
    }

    // --- Zoom and Pan Gesture ---
    private func zoomAndPanGesture() -> some Gesture {
        let magnification = MagnificationGesture()
            .onChanged { value in
                let range = chartXRange ?? (ranges.minX...ranges.maxX)
                let center = (range.lowerBound + range.upperBound) / 2
                let width = (range.upperBound - range.lowerBound) / value
                let newLower = max(ranges.minX, center - width / 2)
                let newUpper = min(ranges.maxX, center + width / 2)
                chartXRange = newLower ... newUpper
            }
            .onEnded { _ in
                dragStartRange = chartXRange
                if let range = chartXRange,
                   range.upperBound - range.lowerBound < 0.1 {
                    chartXRange = ranges.minX ... ranges.maxX
                }
            }

        let drag = DragGesture()
            .onChanged { value in
                if dragStartRange == nil {
                    dragStartRange = chartXRange ?? (ranges.minX ... ranges.maxX)
                }

                guard let startRange = dragStartRange else { return }
                let domainWidth = startRange.upperBound - startRange.lowerBound
                let translationRatio = Double(value.translation.width / 200)
                let delta = translationRatio * domainWidth

                var newLower = startRange.lowerBound - delta
                var newUpper = startRange.upperBound - delta

                if newLower < ranges.minX {
                    let shift = ranges.minX - newLower
                    newLower += shift
                    newUpper += shift
                }
                if newUpper > ranges.maxX {
                    let shift = newUpper - ranges.maxX
                    newLower -= shift
                    newUpper -= shift
                }
                chartXRange = newLower ... newUpper
            }
            .onEnded { _ in
                dragStartRange = chartXRange
            }

        return drag.simultaneously(with: magnification)
    }

    // Snap to the nearest x-value in plotData (for the visible axes)
    private func snapToNearestTickX(at location: CGPoint, chartProxy: ChartProxy) -> Double? {
        guard let xValue = chartProxy.value(atX: location.x, as: Double.self) else { return nil }
        // Find the closest xValue in plotData (across all axes)
        let allX = plotData.map { $0.xValue }
        guard let nearest = allX.min(by: { abs($0 - xValue) < abs($1 - xValue) }) else { return nil }
        return nearest
    }

    // Get the y-value at the exact data point for the axis and x
    private func yValueForAxisAtX(axis: Axis, x: Double) -> Double? {
        plotData.first(where: { $0.axis == axis && $0.xValue == x })?.yValue
    }

    // MARK: - Cursor Logic
    private func setCursor(to xValue: Double) {
        self.selectedX = xValue
        self.showCursorInfo = true
        // Debug: Print all points at this xValue for verification
        let points = plotData.filter { $0.xValue == xValue }
#if DEBUG
        Self.logger.debug("[Cursor] Snapped to x: \(xValue, privacy: .public), points: \(String(describing: points), privacy: .public)")
#endif
    }

    private func clearCursor() {
        self.showCursorInfo = false
        self.selectedX = nil
    }

    private func setDefaultCursorPosition(for data: [IdentifiableGraphPoint]) {
        guard !data.isEmpty else {
            clearCursor()
            return
        }
        var peakPoint: IdentifiableGraphPoint?
        if isFrequencyDomain {
            peakPoint = data.max(by: { $0.yValue < $1.yValue })
        } else {
            peakPoint = data.max(by: { abs($0.yValue) < abs($1.yValue) })
        }
        if let finalPeak = peakPoint {
            setCursor(to: finalPeak.xValue)
        }
    }
}


// --- Preview Setup ---
private struct MultiLineGraphView_PreviewHelper {
    static func generatePreviewSeries(axis: Axis, count: Int, scale: Double, offset: Double = 0) -> [IdentifiableGraphPoint] {
        (0..<count).map { i in IdentifiableGraphPoint(axis: axis, xValue: Double(i)/50.0, yValue: sin((Double(i)/50.0+offset)*4 * .pi)*scale + .random(in: -0.1...0.1)) }
    }
    static func makePlotData() -> [IdentifiableGraphPoint] {
        generatePreviewSeries(axis: .x, count: 100, scale: 1.0) +
        generatePreviewSeries(axis: .y, count: 100, scale: 0.7, offset: 0.5) +
        generatePreviewSeries(axis: .z, count: 100, scale: 0.4, offset: 1.0)
    }
    static func makeRanges(fromPlotData data: [IdentifiableGraphPoint]) -> MultiLineGraphView.AxisRanges {
        .init(minY: -1.5, maxY: 1.5, minX: data.min(by: { $0.xValue < $1.xValue })?.xValue ?? 0, maxX: data.max(by: { $0.xValue < $1.xValue })?.xValue ?? 2.0)
    }
    static let previewPlotData = makePlotData()
    static let previewRanges = makeRanges(fromPlotData: previewPlotData)
    static let previewAxisColors: [Axis: Color] = [.x: .red, .y: .green, .z: .blue]
    static let previewYAxisUnit = "m/s²"
}

#Preview("Time Domain Graph") {
    MultiLineGraphView(
        plotData: MultiLineGraphView_PreviewHelper.previewPlotData,
        ranges: MultiLineGraphView_PreviewHelper.previewRanges,
        isFrequencyDomain: false,
        axisColors: MultiLineGraphView_PreviewHelper.previewAxisColors,
        yAxisLabelUnit: MultiLineGraphView_PreviewHelper.previewYAxisUnit,
        xTicks: Array(stride(from: 0, through: 2, by: 0.5)), // Example ticks
        yTicks: Array(stride(from: -1.5, through: 1.5, by: 0.5)), // Example ticks
        xGridLines: nil,
        yGridLines: nil
    )
    .padding()
    .frame(height: 250)
}
