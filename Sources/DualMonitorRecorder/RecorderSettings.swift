import AppKit
import Foundation
import ScreenCaptureKit
import SwiftUI

struct SavedDisplayPlacement: Codable, Identifiable, Equatable {
    let id: UInt32
    var x: Double
    var y: Double
    var isEnabled: Bool
}

enum RecorderSettings {
    static let askForLocationKey = "askForRecordingLocation"
    static let recordingFolderKey = "recordingFolderPath"
    static let displayPlacementsKey = "displayPlacements"

    static var defaultFolder: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualMonitorRecorder", isDirectory: true)
    }

    static var configuredFolder: URL {
        guard let path = UserDefaults.standard.string(forKey: recordingFolderKey), !path.isEmpty else {
            return defaultFolder
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func displayPlacements() -> [SavedDisplayPlacement] {
        guard let data = UserDefaults.standard.data(forKey: displayPlacementsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedDisplayPlacement].self, from: data)) ?? []
    }

    static func saveDisplayPlacements(_ placements: [SavedDisplayPlacement]) {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        UserDefaults.standard.set(data, forKey: displayPlacementsKey)
    }
}

struct SettingsView: View {
    @AppStorage(RecorderSettings.askForLocationKey) private var askForLocation = false
    @AppStorage(RecorderSettings.recordingFolderKey) private var recordingFolderPath = ""
    @State private var displays: [DisplayConfiguration] = []
    @State private var displayError: String?

    private var displayedFolder: URL {
        recordingFolderPath.isEmpty
            ? RecorderSettings.defaultFolder
            : URL(fileURLWithPath: recordingFolderPath, isDirectory: true)
    }

    var body: some View {
        Form {
            Toggle("녹화할 때마다 저장 위치 묻기", isOn: $askForLocation)

            LabeledContent("기본 저장 위치") {
                Text(displayedFolder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("저장 폴더 변경…") { chooseFolder() }
                Button("기본값으로 복원") { recordingFolderPath = "" }
                    .disabled(recordingFolderPath.isEmpty)
                Spacer()
                Button("Finder에서 열기") {
                    try? FileManager.default.createDirectory(at: displayedFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(displayedFolder)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("녹화 모니터 배치")
                    .font(.headline)
                Text("모니터를 드래그해 영상 안의 위치를 바꾸고, 체크 표시로 녹화 대상을 선택하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisplayArrangementEditor(displays: $displays)
                    .frame(height: 230)

                HStack {
                    Button("실제 배치 불러오기") { loadDisplays(resetPositions: true) }
                    Spacer()
                    if let displayError {
                        Text(displayError).foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
        .task { loadDisplays(resetPositions: false) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "녹화 파일을 저장할 폴더 선택"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = displayedFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recordingFolderPath = url.path
    }

    private func loadDisplays(resetPositions: Bool) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let saved = resetPositions ? [] : RecorderSettings.displayPlacements()
                displays = content.displays.enumerated().map { index, display in
                    let prior = saved.first { $0.id == display.displayID }
                    return DisplayConfiguration(
                        id: display.displayID,
                        name: "모니터 \(index + 1)",
                        width: display.width,
                        height: display.height,
                        x: prior?.x ?? Double(display.frame.origin.x),
                        y: prior?.y ?? Double(display.frame.origin.y),
                        isEnabled: prior?.isEnabled ?? true
                    )
                }
                persistDisplays()
                displayError = nil
            } catch {
                displayError = "모니터 정보를 불러오지 못했습니다."
            }
        }
    }

    private func persistDisplays() {
        RecorderSettings.saveDisplayPlacements(displays.map {
            SavedDisplayPlacement(id: $0.id, x: $0.x, y: $0.y, isEnabled: $0.isEnabled)
        })
    }
}

private struct DisplayConfiguration: Identifiable {
    let id: UInt32
    let name: String
    let width: Int
    let height: Int
    var x: Double
    var y: Double
    var isEnabled: Bool
}

private struct DisplayArrangementEditor: View {
    @Binding var displays: [DisplayConfiguration]
    @State private var dragStarts: [UInt32: CGPoint] = [:]

    var body: some View {
        GeometryReader { geometry in
            let transform = previewTransform(in: geometry.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

                ForEach($displays) { $display in
                    let size = CGSize(
                        width: max(90, CGFloat(display.width) * transform.scale),
                        height: max(55, CGFloat(display.height) * transform.scale)
                    )
                    VStack(spacing: 3) {
                        Toggle(isOn: $display.isEnabled) {
                            Text(display.name).font(.caption.bold())
                        }
                        .toggleStyle(.checkbox)
                        Text("\(display.width) × \(display.height)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: size.width, height: size.height)
                    .background(display.isEnabled ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(display.isEnabled ? Color.accentColor : .gray, lineWidth: 2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .position(
                        x: (CGFloat(display.x) - transform.minX) * transform.scale + size.width / 2 + 12,
                        y: (CGFloat(display.y) - transform.minY) * transform.scale + size.height / 2 + 12
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStarts[display.id] == nil {
                                    dragStarts[display.id] = CGPoint(x: display.x, y: display.y)
                                }
                                guard let start = dragStarts[display.id] else { return }
                                display.x = Double(start.x + value.translation.width / transform.scale)
                                display.y = Double(start.y + value.translation.height / transform.scale)
                            }
                            .onEnded { _ in
                                dragStarts[display.id] = nil
                                save()
                            }
                    )
                    .onChange(of: display.isEnabled) { _ in save() }
                }
            }
        }
    }

    private func previewTransform(in size: CGSize) -> (minX: CGFloat, minY: CGFloat, scale: CGFloat) {
        guard !displays.isEmpty else { return (0, 0, 1) }
        let minX = CGFloat(displays.map(\.x).min() ?? 0)
        let minY = CGFloat(displays.map(\.y).min() ?? 0)
        let maxX = displays.map { CGFloat($0.x) + CGFloat($0.width) }.max() ?? 1
        let maxY = displays.map { CGFloat($0.y) + CGFloat($0.height) }.max() ?? 1
        let scale = min((size.width - 24) / max(1, maxX - minX), (size.height - 24) / max(1, maxY - minY))
        return (minX, minY, max(0.03, scale))
    }

    private func save() {
        RecorderSettings.saveDisplayPlacements(displays.map {
            SavedDisplayPlacement(id: $0.id, x: $0.x, y: $0.y, isEnabled: $0.isEnabled)
        })
    }
}
