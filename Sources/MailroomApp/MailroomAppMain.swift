import AppKit
import SwiftUI
import MailroomFeatures

@main
struct MailroomAppMain: App {
    @State private var app = AppModel(environment: .live)

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        MailroomScene(app: app)
    }
}
