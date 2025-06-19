import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var activeProject = Project(name: "Default Project", description: "", type: .timeHistory)
    var body: some View {
        TabView(selection: $selectedTab) {
            ProjectsView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("Projects")
                }
                .tag(0)
            RealTimeDataView(project: $activeProject)
                .tabItem {
                    Image(systemName: "waveform.path.ecg")
                    Text("Real-Time Data")
                }
                .tag(1)
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(2)
            HelpView()
                .tabItem {
                    Image(systemName: "questionmark.circle")
                    Text("Help")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 0 {
                print("Switched to Projects")
            } else if newValue == 1 {
                print("Switched to Real-Time Data")
            } else if newValue == 2 {
                print("Switched to Settings")
            }
            // Note: oldValue is available but not used in this specific logic.
            // If a case for tag 3 (HelpView) was intended, it would be added here.
        }
    }
}
