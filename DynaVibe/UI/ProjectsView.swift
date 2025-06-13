import SwiftUI

struct ProjectsView: View {
    @State private var projects: [Project] = [] // Placeholder model
    @State private var showingNewProject = false
    
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
        }
    }
}

// Placeholder model and new project form
struct Project: Identifiable {
    let id = UUID()
    var name: String
    var description: String
    var measurements: [Measurement] = []
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
