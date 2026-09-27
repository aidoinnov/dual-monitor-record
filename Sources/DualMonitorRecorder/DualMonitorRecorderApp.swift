import SwiftUI

final class RecorderAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--headless") else { return }
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.orderOut(nil) }
        }
    }
}

@main
struct DualMonitorRecorderApp: App {
    @NSApplicationDelegateAdaptor(RecorderAppDelegate.self) private var appDelegate
    @StateObject private var recorder = DualDisplayRecorder()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(recorder)
                .frame(width: 560, height: 570)
                .onOpenURL { url in
                    switch url.host {
                    case "start": if !recorder.isRecording { recorder.toggleRecording() }
                    case "stop": if recorder.isRecording { recorder.stopRecording() }
                    case "toggle": recorder.toggleRecording()
                    case "settings": SettingsWindowPresenter.shared.show()
                    case "latest": recorder.openSavedVideo()
                    case "identify": if !recorder.isRecording { DisplayOverlayPresenter.shared.showSelectedDisplays() }
                    default: break
                    }
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(recorder)
        } label: {
            Image(systemName: recorder.isRecording ? "record.circle.fill" : "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .frame(width: 600)
                .padding(24)
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var recorder: DualDisplayRecorder
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(recorder.isRecording ? "녹화 중지 (⌘F2)" : "녹화 시작 (⌘F2)") {
            recorder.toggleRecording()
        }
        .disabled(recorder.isBusy)

        if recorder.savedFileURL != nil {
            Divider()
            Button("영상 열기") { recorder.openSavedVideo() }
            Button("저장 폴더 열기") { recorder.revealSavedVideo() }
            if recorder.windowsMP4URL == nil {
                Button("Windows용 MP4 변환") { recorder.convertForWindows() }
                    .disabled(recorder.isConverting)
            } else {
                Button("Windows용 MP4 열기") { recorder.openWindowsVideo() }
            }
        }

        Divider()
        Button("창 열기") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("녹화 모니터 표시") {
            DisplayOverlayPresenter.shared.showSelectedDisplays()
        }
        .disabled(recorder.isRecording || recorder.isBusy)
        Button("설정…") {
            SettingsWindowPresenter.shared.show()
        }
        .keyboardShortcut(",")
        Divider()
        Button("DualMonitorRecorder 종료") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
