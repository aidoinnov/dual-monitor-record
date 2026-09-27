import Foundation
import Network

final class StatusWebSocketServer: @unchecked Sendable {
    static let port: UInt16 = 17843
    private weak var recorder: DualDisplayRecorder?
    private let queue = DispatchQueue(label: "dualrec.websocket")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var timer: DispatchSourceTimer?

    @MainActor
    init(recorder: DualDisplayRecorder) {
        self.recorder = recorder
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            self.listener = listener

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in self?.broadcastStatus() }
            timer.resume()
            self.timer = timer
        } catch {
            print("Unable to start WebSocket server: \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state { self?.remove(id, connection: connection) }
            if case .cancelled = state { self?.remove(id, connection: connection) }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] _, _, _, error in
            guard let self, let connection, error == nil else { return }
            self.receive(on: connection)
        }
    }

    private func remove(_ id: ObjectIdentifier, connection: NWConnection?) {
        connections[id] = nil
        connection?.cancel()
    }

    private func broadcastStatus() {
        Task { @MainActor [weak self] in
            guard let self, let recorder = self.recorder,
                  let data = try? JSONSerialization.data(withJSONObject: recorder.statusPayload, options: [.sortedKeys]) else { return }
            self.queue.async { [weak self] in self?.broadcast(data) }
        }
    }

    private func broadcast(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "dualrec-status", metadata: [metadata])
        for connection in connections.values {
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }
}
