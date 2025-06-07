// DynaVibe/UI/GlobalLiveSummaryCard.swift
import SwiftUI

struct GlobalLiveSummaryCard: View {
    let latestX: Double
    let latestY: Double
    let latestZ: Double
    let unitString: String // New property for the unit

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
                Text(unitString) // Use unitString
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
                Text(unitString) // Use unitString
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
                Text(unitString) // Use unitString
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live acceleration. X: \(formattedValue(latestX)) \(unitString), Y: \(formattedValue(latestY)) \(unitString), Z: \(formattedValue(latestZ)) \(unitString).")
    }
}

// Basic PreviewProvider for GlobalLiveSummaryCard
struct GlobalLiveSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        GlobalLiveSummaryCard(
            latestX: -0.117,
            latestY: -0.086,
            latestZ: 0.692,
            unitString: "m/s²" // Provide sample unit string
        )
        .padding()
        .previewLayout(.sizeThatFits)
        .background(Color.gray.opacity(0.1))

        GlobalLiveSummaryCard(
            latestX: 0.012,
            latestY: 0.009,
            latestZ: 0.070,
            unitString: "g" // Provide sample unit string
        )
        .padding()
        .previewLayout(.sizeThatFits)
        .background(Color.gray.opacity(0.1))
    }
}
