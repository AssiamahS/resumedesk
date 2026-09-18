import SwiftUI

@main
struct ResumeDeskApp: App {
    var body: some Scene {
        WindowGroup {
            EditorView()
                .ignoresSafeArea(.container, edges: .bottom)
                .onOpenURL { EditorController.current?.importURL($0) }
        }
    }
}

struct EditorView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EditorController { EditorController() }
    func updateUIViewController(_ controller: EditorController, context: Context) {}
}
