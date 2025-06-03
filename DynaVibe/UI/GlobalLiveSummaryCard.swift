// DynaVibe/UI/GlobalLiveSummaryCard.swift
import SwiftUI

struct GlobalLiveSummaryCard: View {
    let latestX: Double
    let latestY: Double
    let latestZ: Double

    private func formattedValue(_ value: Double) -> String {
        return String(format: "%.3f", value)
    }

    var body: some View {
        HStack(spacing: 15) {
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                Text("X-axis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formattedValue(latestX))
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                Text("m/s²")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Divider().frame(maxHeight: 40)
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                Text("Y-axis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formattedValue(latestY))
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                Text("m/s²")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Divider().frame(maxHeight: 40)
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                Text("Z-axis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formattedValue(latestZ))
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                Text("m/s²")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10) // Keep original vertical padding
        .padding(.horizontal, 8) // Keep original horizontal padding
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10) // Changed from 12 to 10 as per example in prompt
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live acceleration. X: \(formattedValue(latestX)) meters per second squared, Y: \(formattedValue(latestY)) meters per second squared, Z: \(formattedValue(latestZ)) meters per second squared.")
    }
}

// Basic PreviewProvider for GlobalLiveSummaryCard
struct GlobalLiveSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        GlobalLiveSummaryCard(
            latestX: -0.117,
            latestY: -0.086,
            latestZ: 0.692
        )
        .padding()
        .previewLayout(.sizeThatFits)
        .background(Color.gray.opacity(0.1))
    }
}
