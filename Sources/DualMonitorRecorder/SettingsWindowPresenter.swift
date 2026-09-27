import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowPresenter()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let settingsView = SettingsView()
                .frame(width: 600)
                .padding(24)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 648, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "DualMonitorRecorder 설정"
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
