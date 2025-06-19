import SwiftUI

struct AssessmentFlowView: View {
    @Binding var project: Project
    @State private var step: Step = .setup

    enum Step {
        case setup, measurement, review
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }

    var body: some View {
        switch step {
        case .setup:
            VStack(spacing: 20) {
                Text(setupTitle)
                    .font(.headline)
                Text(setupDescription)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Start Measurement") { step = .measurement }
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Setup")
        case .measurement:
            RealTimeDataView(project: $project)
                .navigationBarItems(trailing: Button("Next") { step = .review })
        case .review:
            List(project.measurements) { m in
                Text("Measurement on \(m.date, formatter: dateFormatter)")
            }
            .navigationTitle("Results")
        }
    }

    private var setupTitle: String {
        project.type == .floorVibration ? "Floor Vibration Setup" : "Measurement Setup"
    }

    private var setupDescription: String {
        switch project.type {
        case .floorVibration:
            return "Place the sensor on the floor and ensure proper contact before starting the recording."
        case .timeHistory:
            return "Prepare to record time history data."
        }
    }
}
