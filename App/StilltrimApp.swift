import SwiftUI

@main
struct StilltrimApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase) {
                    if scenePhase == .active { model.access.refresh() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.access.canRead {
                HomeView()
            } else {
                WelcomeView()
            }
        }
        .task { model.startScanIfRequestedByLaunchArguments() }
    }
}
