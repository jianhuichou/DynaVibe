import SwiftUI

struct ProjectsView: View {
    @State private var projects: [Project] = []
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
                    List {
                        ForEach($projects) { $project in
                            NavigationLink(destination: AssessmentFlowView(project: $project)) {
                                VStack(alignment: .leading) {
                                    Text(project.name)
                                        .font(.headline)
                                    Text(project.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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

struct NewProjectView: View {
    var onSave: (Project) -> Void
    @Environment(\.presentationMode) var presentationMode
    @State private var name = ""
    @State private var description = ""
    @State private var type: ProjectType = .timeHistory
    @State private var buildingType: BuildingType = .office
    @State private var construction: ConstructionMaterial = .concrete
    var body: some View {
        NavigationView {
            Form {
                TextField("Project Name", text: $name)
                TextField("Description", text: $description)
                Picker("Project Type", selection: $type) {
                    ForEach(ProjectType.allCases) { Text($0.rawValue).tag($0) }
                }
                if type == .floorVibration {
                    Picker("Building Type", selection: $buildingType) {
                        ForEach(BuildingType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Construction Material", selection: $construction) {
                        ForEach(ConstructionMaterial.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Section(header: Text("Subjective Assessment")) {
                        Text("Survey coming soon")
                    }
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { Haptics.tap(); presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Haptics.tap()
                        var project = Project(name: name, description: description, type: type)
                        if type == .floorVibration {
                            project.buildingType = buildingType
                            project.constructionMaterial = construction
                        }
                        onSave(project)
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
