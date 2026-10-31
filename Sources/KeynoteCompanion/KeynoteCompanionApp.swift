import AppKit
import SwiftUI

@main
struct KeynoteCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarLabel(state: model.state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The bundle sets LSUIElement; this covers `swift run`, which has no bundle.
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MenuBarLabel: View {
    let state: SlideState

    var body: some View {
        if state.keynoteRunning && state.slide > 0 {
            Label("\(state.slide)", systemImage: state.playing ? "play.rectangle.fill" : "play.rectangle")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "play.rectangle")
        }
    }
}
