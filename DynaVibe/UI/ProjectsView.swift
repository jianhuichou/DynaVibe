import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var showingNewProject = false

    var body: some View {
        NavigationView {
            VStack {
                if projects.isEmpty {
                    Text("No projects yet. Tap + to add one.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(projects) { project in
                            VStack(alignment: .leading) {
                                Text(project.name)
                                    .font(.headline)
                                Text(project.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete(perform: deleteProjects)
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
                NewProjectView()
            }
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(projects[index]) }
    }
}

struct NewProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var type = ""
    var body: some View {
        NavigationView {
            Form {
                TextField("Project Name", text: $name)
                TextField("Type", text: $type)
                TextField("Description", text: $description)
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { Haptics.tap(); dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Haptics.tap()
                        let project = Project(name: name, description: description, type: type)
                        modelContext.insert(project)
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
