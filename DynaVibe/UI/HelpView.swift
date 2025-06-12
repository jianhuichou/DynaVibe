import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to DynaVibe")
                    .font(.largeTitle)
                    .bold()
                Text("This app lets you record, analyze, and export vibration data from your device sensors.")
                
                Group {
                    Text("Getting Started")
                        .font(.title2)
                        .bold()
                    Text("1. Go to **Real-Time Data** to start measurements.\n2. Adjust settings under **Settings**.\n3. View saved projects under **Projects**.\n4. Export your data as CSV.\n5. Switch to Frequency mode using the graph toggle to see FFT results.")
                }
                
                Group {
                    Text("Tips")
                        .font(.title2)
                        .bold()
                    Text("• Keep your device steady when testing.\n• Use the 'Subtract Gravity' option to get linear acceleration.\n• Watch the sample count and time left for better control.\n• Check min/max values to monitor extreme events.")
                }
            }
            .padding()
        }
        .navigationTitle("Help & Guide")
    }
}
