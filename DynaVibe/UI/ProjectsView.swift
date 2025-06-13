import SwiftUI

struct ProjectsView: View {
    @State private var projects: [Project] = [] // Placeholder model
    @State private var showingNewProject = false
    @State private var exportURL: URL? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                if projects.isEmpty {
                    Text("No projects yet. Tap + to add one.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(projects) { project in
                        VStack(alignment: .leading) {
                            Text(project.name)
                                .font(.headline)
                            Text(project.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .contextMenu {
                            Button("Export Report") {
                                Haptics.tap()
                                exportReport(for: project)
                            }
                            Button("Export Raw Data") {
                                Haptics.tap()
                                exportCSV(for: project)
                            }
                            Button("Export FFT") {
                                Haptics.tap()
                                exportFFT(for: project)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Haptics.tap(); showingNewProject = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView(onSave: { newProject in
                    projects.append(newProject)
                    showingNewProject = false
                })
            }
            .sheet(item: $exportURL) { url in
                ActivityView(url: url)
            }
        }
    }

    // MARK: - Export helpers
    private func exportReport(for project: Project) {
        let metrics = [ReportMetric(title: "Sample Metric", value: "0.0")]
        let image = UIImage(systemName: "chart.bar") ?? UIImage()
        if let url = ReportGenerator.generatePDF(title: project.name, metrics: metrics, chart: image) {
            exportURL = url
        }
    }

    private func exportCSV(for project: Project) {
        let sample: [(timestamp: TimeInterval, x: Double, y: Double, z: Double)] = []
        if let url = CSVExporter.exportAccelerationData(sample) {
            exportURL = url
        }
    }

    private func exportFFT(for project: Project) {
        let freqs: [Double] = []
        let mags: [Double] = []
        if let url = CSVExporter.exportFFTData(frequencies: freqs, magnitudes: mags) {
            exportURL = url
        }
    }
}

// Placeholder model and new project form
struct Project: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}

struct NewProjectView: View {
    var onSave: (Project) -> Void
    @Environment(\.presentationMode) var presentationMode
    @State private var name = ""
    @State private var description = ""
    var body: some View {
        NavigationView {
            Form {
                TextField("Project Name", text: $name)
                TextField("Description", text: $description)
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { Haptics.tap(); presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Haptics.tap()
                        onSave(Project(name: name, description: description))
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

// Allow using URL with .sheet(item:)
extension URL: Identifiable {
    public var id: String { absoluteString }
}
