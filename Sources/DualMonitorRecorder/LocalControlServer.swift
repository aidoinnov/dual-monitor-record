import Foundation
import Network

final class LocalControlServer: @unchecked Sendable {
    static let port: UInt16 = 17842
    private weak var recorder: DualDisplayRecorder?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dualrec.local-api")

    @MainActor
    init(recorder: DualDisplayRecorder) {
        self.recorder = recorder
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { print("Local API failed: \(error)") }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("Unable to start local API: \(error)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel(); return
            }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            let method = parts.first.map(String.init) ?? "GET"
            let path = parts.count > 1 ? String(parts[1]).split(separator: "?").first.map(String.init) ?? "/" : "/"
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder else { return }
                let result: ([String: Any], Int)
                switch (method, path) {
                case ("GET", "/v1/status"):
                    result = (recorder.statusPayload, 200)
                case ("POST", "/v1/recording/start"):
                    if !recorder.isRecording { recorder.toggleRecording() }
                    result = (["ok": true, "action": "start"], 202)
                case ("POST", "/v1/recording/stop"):
                    if recorder.isRecording { recorder.stopRecording() }
                    result = (["ok": true, "action": "stop"], 202)
                case ("POST", "/v1/recording/toggle"):
                    recorder.toggleRecording()
                    result = (["ok": true, "action": "toggle"], 202)
                case ("POST", "/v1/latest/open"):
                    recorder.openSavedVideo()
                    result = (["ok": recorder.savedFileURL != nil], 200)
                case ("POST", "/v1/latest/reveal"):
                    recorder.revealSavedVideo()
                    result = (["ok": recorder.savedFileURL != nil], 200)
                default:
                    result = (["error": "not_found", "path": path], 404)
                }
                self.respond(connection, payload: result.0, status: result.1)
            }
        }
    }

    private func respond(_ connection: NWConnection, payload: [String: Any], status: Int) {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 202 ? "Accepted" : "Not Found"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
