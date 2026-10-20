import SwiftUI

@MainActor
@main
struct TindeqScrollingApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { await model.refreshInstagramStatus() }
        }
    }
}
