// UI/MetricSummaryCard.swift
import SwiftUI

struct MetricSummaryCard: View {
    let latestX: Double
    let latestY: Double
    let latestZ: Double
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
    let minZ: Double
    let maxZ: Double
    // Add RMS properties
    let rmsX: Double? // Making them optional to align with MetricColumn
    let rmsY: Double?
    let rmsZ: Double?

    // No local formattedValue needed as MetricColumn handles its own display

    var body: some View {
        HStack(alignment: .top, spacing: 8) { // .top alignment for columns, adjust spacing
            MetricColumn(title: "X‑axis", value: latestX, minValue: minX, maxValue: maxX, unit: "m/s²", rmsValue: rmsX)
            Spacer()
            MetricColumn(title: "Y‑axis", value: latestY, minValue: minY, maxValue: maxY, unit: "m/s²", rmsValue: rmsY)
            Spacer()
            MetricColumn(title: "Z‑axis", value: latestZ, minValue: minZ, maxValue: maxZ, unit: "m/s²", rmsValue: rmsZ)
        }
        .padding(.vertical, 10) // Add some vertical padding inside the card
        .padding(.horizontal, 8) // Add some horizontal padding inside the card
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(UIColor.systemGray6), Color(UIColor.systemGray5)]), // Softer gradient
                startPoint: .top,
                endPoint: .bottom
            )
            .cornerRadius(12) // Slightly less corner radius
        )
        //.shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2) // Softer shadow
        // Accessibility label can be simplified or improved if needed
        .accessibilityElement(children: .ignore) // Ignore children if providing a good combined label
        .accessibilityLabel("Vibration summary. X: \(latestX, specifier: "%.3f"), Y: \(latestY, specifier: "%.3f"), Z: \(latestZ, specifier: "%.3f") meters per second squared.")
    }
}

#Preview {
    MetricSummaryCard(
        latestX: -0.117, latestY: -0.086, latestZ: 0.692,
        minX: -0.705, maxX: 1.383,
        minY: -0.658, maxY: 0.891,
        minZ: -7.910, maxZ: 8.108,
        rmsX: 0.450, rmsY: 0.300, rmsZ: 1.200
    )
    .padding()
}
