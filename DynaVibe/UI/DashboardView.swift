// DashboardView.swift
import SwiftUI

// Ensure Axis enum is accessible here (e.g., from Shared/AxisAndLegend.swift if it's in the target)
// Ensure DataPoint struct is accessible here (e.g., from Models/DataPoint.swift if it's in the target)

private struct MetricRow: View {
    let label: String
    let value: Double?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value != nil ? String(format: "%.3f", value!) : "N/A")
                .foregroundColor(value != nil ? .primary : .secondary)
        }
    }
}

struct DashboardView: View {
    @StateObject private var viewModel = AccelerationViewModel()

    private var hasData: Bool {
        return viewModel.collectedSamplesCount > 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Extrema (m/s²)") {
                    MetricRow(label: "Min X", value: viewModel.minX)
                    MetricRow(label: "Max X", value: viewModel.maxX)
                    MetricRow(label: "Min Y", value: viewModel.minY)
                    MetricRow(label: "Max Y", value: viewModel.maxY)
                    MetricRow(label: "Min Z", value: viewModel.minZ)
                    MetricRow(label: "Max Z", value: viewModel.maxZ)
                }

                Section("Peak FFT (Hz)") {
                    MetricRow(label: "X", value: viewModel.peakFrequencyX)
                    MetricRow(label: "Y", value: viewModel.peakFrequencyY)
                    MetricRow(label: "Z", value: viewModel.peakFrequencyZ)
                }
                // Display RMS if data is completed
                if viewModel.measurementState == .completed && hasData {
                    Section("Overall RMS (m/s²)") {
                        MetricRow(label: "RMS X", value: viewModel.rmsX)
                        MetricRow(label: "RMS Y", value: viewModel.rmsY)
                        MetricRow(label: "RMS Z", value: viewModel.rmsZ)
                    }
                }
            }
            .navigationTitle("Analysis Summary") // Changed title for clarity
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // CORRECTED: Call the method directly
                        viewModel.exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!hasData || viewModel.measurementState != .completed) // Also disable if not completed
                }
            }
        }
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
