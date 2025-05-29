// UI/MetricColumn.swift
import SwiftUI

struct MetricColumn: View {
    let title: String
    let value: Double
    let minValue: Double
    let maxValue: Double
    let unit: String
    let rmsValue: Double? // New optional property for RMS

    var decimals: Int = 3
    var statusColor: Color = .primary

    // Formatter for general values (current, min, max)
    private func formatValue(_ val: Double, forceScientificAbove: Double = 10000, forceScientificBelow: Double = 0.001) -> String {
        let absVal = abs(val)
        if val.isNaN || !val.isFinite { return "N/A" }
        if absVal == 0 { return String(format: "%.\(decimals)f", 0.0) } // Handle exactly zero
        if absVal < forceScientificBelow || absVal > forceScientificAbove {
            return String(format: "%.2e", val)
        } else {
            return String(format: "%.\(decimals)f", val)
        }
    }

    // Specific formatter for RMS, maybe fewer decimals or different rules
    private var formattedRmsValue: String? {
        guard let rms = rmsValue else { return nil }
        if rms.isNaN || !rms.isFinite { return "N/A" }
        return String(format: "%.3f", rms) // RMS typically shown with fixed decimals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) { // Increased spacing slightly
            Text(title)
                .font(.caption)
                .fontWeight(.medium) // Slightly bolder title
                .foregroundColor(.secondary)
            
            Text("\(formatValue(value)) \(unit)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundColor(statusColor)

            // Min/Max Section
            HStack(spacing: 4) { // Put Min/Max on one line if space allows, or keep separate
                Text("Min:")
                Text(formatValue(minValue, forceScientificAbove: .infinity, forceScientificBelow: 0)) // Don't force scientific for min/max readily
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Text("Max:")
                Text(formatValue(maxValue, forceScientificAbove: .infinity, forceScientificBelow: 0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            // RMS Value Display
            if let rmsStr = formattedRmsValue {
                HStack(spacing: 4) {
                    Text("RMS:")
                    Text(rmsStr) // Already includes unit if needed, or add unit here
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.caption2) // Consistent with Min/Max
                .foregroundColor(Color.orange) // Differentiate RMS color, or use .secondary
                .padding(.top, 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)")
        .accessibilityValue("\(formatValue(value)) \(unit), Min: \(formatValue(minValue)), Max: \(formatValue(maxValue))" + (formattedRmsValue != nil ? ", RMS: \(formattedRmsValue!)" : ""))
    }
}

#Preview {
    VStack {
        MetricColumn(title: "X-axis", value: -0.11752, minValue: -0.705, maxValue: 1.383, unit: "m/s²", rmsValue: 0.456)
        MetricColumn(title: "Y-axis", value: 0.000086, minValue: -0.658, maxValue: 0.891, unit: "m/s²", rmsValue: 0.321, statusColor: .green)
        MetricColumn(title: "Z-axis", value: 12345.924, minValue: -7.910, maxValue: 8.108, unit: "m/s²", rmsValue: nil) // Test nil RMS
    }
    .padding()
}
