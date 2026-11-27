import SwiftUI

@main
struct KJVStudyBibleApp: App {
    @StateObject private var viewModel = BibleWorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            ScriptureWorkspaceView(viewModel: viewModel)
        }
    }
}
