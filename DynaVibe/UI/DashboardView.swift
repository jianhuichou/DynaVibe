// UI/DashboardView.swift
import SwiftUI

private struct MetricRow: View {
    let label: String
    let value: Double?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            // The view model now provides display-ready properties that handle unit conversion.
            // This view doesn't need to format the number itself, just handle the optional.
            Text(value != nil ? String(format: "%.3f", value!) : "N/A")
                .foregroundColor(value != nil ? .primary : .secondary)
        }
    }
}

struct DashboardView: View {
    // The Dashboard now likely shares an instance of the view model from a higher-level view,
    // or creates its own. @StateObject is appropriate if this view "owns" the model.
    @StateObject private var viewModel = AccelerationViewModel()

    // This computed property correctly checks the sample count from the view model
    private var hasData: Bool {
        // Accessing a simple property like this is fine.
        return (viewModel.timeSeriesData[.x]?.count ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            List {
                // The view model provides display-ready, optional values which are unit-converted.
                Section("Extrema (\(viewModel.currentUnitString))") {
                    MetricRow(label: "Min X", value: viewModel.displayMinX)
                    MetricRow(label: "Max X", value: viewModel.displayMaxX)
                    MetricRow(label: "Min Y", value: viewModel.displayMinY)
                    MetricRow(label: "Max Y", value: viewModel.displayMaxY)
                    MetricRow(label: "Min Z", value: viewModel.displayMinZ)
                    MetricRow(label: "Max Z", value: viewModel.displayMaxZ)
                }

                Section("Peak FFT (Hz)") {
                    MetricRow(label: "X", value: viewModel.peakFrequencyX)
                    MetricRow(label: "Y", value: viewModel.peakFrequencyY)
                    MetricRow(label: "Z", value: viewModel.peakFrequencyZ)
                }
                
                // Display RMS if data is completed
                if viewModel.measurementState == .completed && hasData {
                    Section("Overall RMS (\(viewModel.currentUnitString))") {
                        MetricRow(label: "RMS X", value: viewModel.displayRmsX)
                        MetricRow(label: "RMS Y", value: viewModel.displayRmsY)
                        MetricRow(label: "RMS Z", value: viewModel.displayRmsZ)
                    }
                }
            }
            .navigationTitle("Analysis Summary")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // [FIXED] Correctly call the exportCSV() function with parentheses.
                        viewModel.exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!hasData || viewModel.measurementState != .completed)
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
