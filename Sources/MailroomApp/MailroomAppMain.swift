import AppKit
import SwiftUI
import MailroomFeatures

@main
struct MailroomAppMain: App {
    @State private var vm = DeckViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        MailroomScene(vm: vm)
    }
}
