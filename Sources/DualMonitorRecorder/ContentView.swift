import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var recorder: DualDisplayRecorder
    @State private var showFileImporter = false
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: recorder.isRecording ? "record.circle.fill" : "rectangle.on.rectangle")
                .font(.system(size: 58))
                .foregroundStyle(recorder.isRecording ? .red : .blue)

            VStack(spacing: 7) {
                Text("듀얼 모니터 녹화")
                    .font(.title.bold())
                Text(recorder.status)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 430)
            }

            if recorder.isRecording {
                Text(recorder.elapsedText)
                    .font(.system(.title2, design: .monospaced).bold())
                    .foregroundStyle(.red)
            }

            Button {
                recorder.toggleRecording()
            } label: {
                Label(
                    recorder.isRecording ? "녹화 중지" : "녹화 시작",
                    systemImage: recorder.isRecording ? "stop.fill" : "record.circle"
                )
                .frame(width: 150)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .blue)
            .disabled(recorder.isBusy)

            Text("단축키: ⌘F2 · 창을 닫아도 메뉴 막대에서 계속 사용할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("설정", systemImage: "gearshape") {
                SettingsWindowPresenter.shared.show()
            }
            .buttonStyle(.link)

            Button("녹화 모니터 표시", systemImage: "display.2") {
                DisplayOverlayPresenter.shared.showSelectedDisplays()
            }
            .buttonStyle(.bordered)
            .disabled(recorder.isRecording || recorder.isBusy)

            if recorder.savedFileURL != nil && !recorder.isRecording {
                HStack(spacing: 12) {
                    Button("폴더 열기", systemImage: "folder") {
                        recorder.revealSavedVideo()
                    }
                    Button("영상 열기", systemImage: "play.rectangle") {
                        recorder.openSavedVideo()
                    }
                    if recorder.windowsMP4URL == nil {
                        Button("Windows MP4 변환", systemImage: "arrow.triangle.2.circlepath") {
                            recorder.convertForWindows()
                        }
                        .disabled(recorder.isConverting)
                    } else {
                        Button("MP4 열기", systemImage: "play.rectangle.fill") {
                            recorder.openWindowsVideo()
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 7) {
                Image(systemName: recorder.isConverting ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                    .font(.title2)
                Text(recorder.isConverting
                     ? "Windows용 MP4 변환 중 \(recorder.conversionProgress)"
                     : "MOV · MP4 · M4V 파일을 여기에 드래그")
                    .font(.callout.weight(.medium))
                Button("파일 선택…") { showFileImporter = true }
                    .buttonStyle(.link)
                    .disabled(recorder.isConverting || recorder.isRecording)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isDropTarget ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .dropDestination(for: URL.self) { urls, _ in
                recorder.convertDroppedFiles(urls)
                return !urls.isEmpty
            } isTargeted: { isDropTarget = $0 }

            Text("설정에서 선택하고 배치한 모니터들이 하나의 MOV 파일로 저장됩니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .onAppear { recorder.startRemoteControl() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { recorder.convertDroppedFiles(urls) }
        }
    }
}
