// DynaVibe/UI/AxisMetricCard.swift
import SwiftUI

struct AxisMetricCard: View {
    let title: String
    let value: Double? // For the main metric, e.g., RMS value
    let unit: String
    let peakFrequency: Double? // Optional peak frequency

    private var formattedValue: String {
        guard let val = value else { return "N/A" }
        // Format to 2 decimal places for typical g values, adjust if needed
        return String(format: "%.2f", val)
    }

    private var formattedPeakFrequency: String? {
        guard let freq = peakFrequency else { return nil }
        // Format to 1 decimal place for frequency
        return String(format: "%.1f Hz", freq)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { // Slightly more spacing
            Text(title)
                .font(.headline) // More prominent title
                .foregroundColor(.secondary) // Standard secondary color for titles

            HStack(alignment: .firstTextBaseline, spacing: 2) { // Align baselines of value and unit
                Text(formattedValue)
                    .font(.system(size: 24, weight: .semibold, design: .rounded)) // Larger, rounded font for value
                    .lineLimit(1) // Ensure value fits
                    .minimumScaleFactor(0.7) // Allow scaling down if too large
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 1) // Slight space before unit
            }

            // Conditionally display Peak Frequency
            if let freqStr = formattedPeakFrequency {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill") // Example icon for peak frequency
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text(freqStr)
                        .font(.caption)
                        .foregroundColor(.orange) // Consistent color for peak freq info
                }
            } else {
                // Placeholder to maintain height if peak frequency is not available
                // This ensures cards in an HStack have similar heights.
                // Alternatively, use .frame(height: ...) on the VStack if all cards should have fixed height.
                Text("") // Empty text as a spacer
                    .font(.caption) // Match font to keep spacing consistent
            }
        }
        .padding(12) // Uniform padding
        .frame(minWidth: 130, idealWidth: 150) // Give it some min/ideal width for consistency in ScrollView
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12) // Slightly larger radius
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1) // Softer shadow
    }
}

struct AxisMetricCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                AxisMetricCard(title: "RMS X", value: 0.4567, unit: "g", peakFrequency: 120.52)
                AxisMetricCard(title: "RMS Y", value: 0.3012, unit: "g", peakFrequency: nil)
                AxisMetricCard(title: "RMS Z", value: nil, unit: "g", peakFrequency: 80.0)
                AxisMetricCard(title: "Displacement", value: 12.345, unit: "mils", peakFrequency: 60)
            }
            .padding()
        }
        .background(Color(UIColor.systemGray4)) // Background for preview area
        .previewLayout(.sizeThatFits) // Ensure previews are sized nicely
    }
}
