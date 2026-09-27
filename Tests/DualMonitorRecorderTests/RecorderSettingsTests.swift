import XCTest
@testable import DualMonitorRecorder

final class RecorderSettingsTests: XCTestCase {
    func testDisplayPlacementJSONRoundTrip() throws {
        let expected = [
            SavedDisplayPlacement(id: 11, x: -1920, y: 0, isEnabled: true),
            SavedDisplayPlacement(id: 22, x: 0, y: 240, isEnabled: false)
        ]
        let data = try JSONEncoder().encode(expected)
        XCTAssertEqual(try JSONDecoder().decode([SavedDisplayPlacement].self, from: data), expected)
    }

    func testDefaultRecordingFolderIsInsideMovies() {
        XCTAssertEqual(RecorderSettings.defaultFolder.lastPathComponent, "DualMonitorRecorder")
        XCTAssertTrue(RecorderSettings.defaultFolder.path.contains("Movies"))
    }

    func testConfiguredFolderUsesStoredValue() {
        let key = RecorderSettings.recordingFolderKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("/tmp/dualrec-test-output", forKey: key)
        XCTAssertEqual(RecorderSettings.configuredFolder.path, "/tmp/dualrec-test-output")
    }

    func testPixelAlignmentKeepsCanvasOriginAtZero() {
        XCTAssertEqual(PixelAlignment.coordinate(0), 0)
        XCTAssertEqual(PixelAlignment.coordinate(1), 0)
        XCTAssertEqual(PixelAlignment.coordinate(3), 2)
        XCTAssertEqual(PixelAlignment.size(0), 2)
        XCTAssertEqual(PixelAlignment.size(3), 2)
    }

    func testWindowsConversionOutputNeverOverwritesInput() {
        XCTAssertEqual(
            WindowsVideoConverter.outputURL(for: URL(fileURLWithPath: "/tmp/session.mov")).path,
            "/tmp/session-windows.mp4"
        )
        XCTAssertEqual(
            WindowsVideoConverter.outputURL(for: URL(fileURLWithPath: "/tmp/session-windows.mp4")).path,
            "/tmp/session-windows-converted.mp4"
        )
    }
}
