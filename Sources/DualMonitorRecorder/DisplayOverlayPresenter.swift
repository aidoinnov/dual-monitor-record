import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class DisplayOverlayPresenter {
    static let shared = DisplayOverlayPresenter()
    private var windows: [NSPanel] = []
    private var dismissTask: Task<Void, Never>?

    func showSelectedDisplays() {
        hide()
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let saved = RecorderSettings.displayPlacements()
                let enabledIDs = Set(saved.filter(\.isEnabled).map(\.id))
                let selected = saved.isEmpty
                    ? content.displays
                    : content.displays.filter { enabledIDs.contains($0.displayID) }

                for (index, display) in selected.enumerated() {
                    let matchedByID = NSScreen.screens.first(where: {
                        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
                    })
                    let matchedByFrame = NSScreen.screens.first(where: {
                        Int($0.frame.origin.x) == Int(display.frame.origin.x)
                            && Int($0.frame.origin.y) == Int(display.frame.origin.y)
                    })
                    guard let screen = matchedByID ?? matchedByFrame else { continue }
                    windows.append(makeWindow(screen: screen, number: index + 1, display: display))
                }

                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.hide() }
                }
            } catch {
                hide()
            }
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(screen: NSScreen, number: Int, display: SCDisplay) -> NSPanel {
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.setFrame(screen.frame, display: true)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: DisplayOverlayView(
            number: number,
            resolution: "\(display.width) × \(display.height)"
        ))
        window.orderFrontRegardless()
        return window
    }
}

private struct DisplayOverlayView: View {
    let number: Int
    let resolution: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.accentColor, lineWidth: 14)
                .padding(18)
            VStack(spacing: 10) {
                Text("녹화 모니터 \(number)")
                    .font(.system(size: 54, weight: .bold))
                Text(resolution)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 46)
            .padding(.vertical, 30)
            .foregroundStyle(.white)
            .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 18)
        }
    }
}
