import AppIntents
import AppKit

struct StartDualRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "듀얼 모니터 녹화 시작"
    static let description = IntentDescription("DualMonitorRecorder에서 선택한 모니터 녹화를 시작합니다.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NSWorkspace.shared.open(URL(string: "dualrecorder://start")!)
        return .result()
    }
}

struct StopDualRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "듀얼 모니터 녹화 중지"
    static let description = IntentDescription("현재 녹화를 중지하고 영상을 저장합니다.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NSWorkspace.shared.open(URL(string: "dualrecorder://stop")!)
        return .result()
    }
}

struct DualRecorderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDualRecordingIntent(),
            phrases: ["\(.applicationName) 녹화 시작", "\(.applicationName)에서 화면 녹화"],
            shortTitle: "녹화 시작",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopDualRecordingIntent(),
            phrases: ["\(.applicationName) 녹화 중지"],
            shortTitle: "녹화 중지",
            systemImageName: "stop.circle"
        )
    }
}
