#if DEBUG
import SwiftUI

struct DebugMenuView: View {
    var body: some View {
        List {
            Section("UI") {
                NavigationLink {
                    DesignSystemGalleryView()
                } label: {
                    Label("Design system", systemImage: "paintpalette")
                }

                NavigationLink {
                    ComponentStatesDebugView()
                } label: {
                    Label("Komponentstates", systemImage: "square.stack.3d.up")
                }

                NavigationLink {
                    EmptyStatesDebugView()
                } label: {
                    Label("Tomtilstander", systemImage: "tray")
                }
            }

            Section {
                NavigationLink {
                    DemoDataDebugView()
                } label: {
                    Label("Demo-data", systemImage: "shippingbox")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Interne utviklerverktøy for rask UI-iterasjon, demo-data og visuell QA.")
            }
        }
        .navigationTitle("Debug")
    }
}

#Preview {
    NavigationStack {
        DebugMenuView()
    }
}
#endif
