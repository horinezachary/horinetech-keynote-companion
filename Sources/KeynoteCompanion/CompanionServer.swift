import Foundation
import KeynoteCompanionCore
import Network

/// The TCP server Companion connects to. Everything runs on the main queue; traffic is tiny.
final class CompanionServer {
    struct Config: Equatable {
        var port: UInt16
        var allowRemote: Bool
    }

    /// Called for each command from an authorised client.
    var onCommand: ((Command, ClientConnection) -> Void)?
    var onClientsChanged: ((Int) -> Void)?
    var onStatus: ((String) -> Void)?
    /// The state to greet new clients with.
    var currentState: () -> SlideState? = { nil }
    /// Read at each hello, so changing it does not drop connected clients.
    var token: () -> String = { "" }

    let appVersion: String
    private var listener: NWListener?
    private var clients: [UUID: ClientConnection] = [:]
    private var heartbeat: Timer?
    private(set) var config: Config?

    init(appVersion: String) {
        self.appVersion = appVersion
    }

    var authorisedCount: Int { clients.values.filter(\.authorised).count }

    func start(_ config: Config) {
        stop()
        self.config = config
        guard let port = NWEndpoint.Port(rawValue: config.port), config.port > 0 else {
            onStatus?("Invalid port \(config.port)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            if config.allowRemote {
                listener = try NWListener(using: params, on: port)
            } else {
                params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
                listener = try NWListener(using: params)
            }
        } catch {
            onStatus?("Could not listen on port \(config.port): \(error.localizedDescription)")
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onStatus?("Listening on port \(config.port)")
            case .failed(let error):
                self.onStatus?("Port \(config.port) unavailable: \(error.localizedDescription)")
                self.listener?.cancel()
                self.listener = nil
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .main)
        self.listener = listener

        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.broadcast(HeartbeatMessage())
        }
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        listener?.cancel()
        listener = nil
        for client in clients.values { client.close() }
        clients.removeAll()
        onClientsChanged?(0)
    }

    /// Sends a message to every authorised client.
    func broadcast<T: Encodable>(_ message: T) {
        let line = WireCodec.line(message)
        for client in clients.values where client.authorised {
            client.send(line)
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let client = ClientConnection(connection: connection)
        clients[client.id] = client
        client.onLine = { [weak self, weak client] line in
            guard let self, let client else { return }
            self.handle(line, from: client)
        }
        client.onClose = { [weak self, weak client] in
            guard let self, let client else { return }
            self.clients[client.id] = nil
            self.onClientsChanged?(self.authorisedCount)
        }
        client.start()

        if token().isEmpty {
            // No token: greet straight away, so a hand-typed `nc` session works.
            authorise(client)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak client] in
                guard let client, !client.authorised else { return }
                client.send(WireCodec.line(ErrorMessage(code: "auth", message: "No hello received")))
                client.close()
            }
        }
    }

    private func handle(_ line: Data, from client: ClientConnection) {
        switch WireCodec.decode(line) {
        case .hello(let given):
            guard !client.authorised else { return }
            if (given ?? "") == token() {
                authorise(client)
            } else {
                client.send(WireCodec.line(ErrorMessage(code: "auth", message: "Wrong or missing token")))
                client.close()
            }
        case .command(let command):
            guard client.authorised else { return }
            onCommand?(command, client)
        case .unknown:
            break
        }
    }

    private func authorise(_ client: ClientConnection) {
        client.authorised = true
        client.send(WireCodec.line(HelloMessage(version: appVersion)))
        if let state = currentState() {
            client.send(WireCodec.line(state))
        }
        onClientsChanged?(authorisedCount)
    }
}

final class ClientConnection {
    let id = UUID()
    var authorised = false
    var onLine: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private let connection: NWConnection
    private var buffer = LineBuffer()
    private var closed = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.finish()
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ data: Data) {
        guard !closed else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.close() }
        })
    }

    func close() {
        guard !closed else { return }
        // Let queued sends (such as an auth error) go out before cancelling.
        let connection = self.connection
        connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
        finish()
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        onClose?()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                for line in self.buffer.append(data) {
                    self.onLine?(line)
                }
            }
            if isComplete || error != nil {
                self.connection.cancel()
                self.finish()
            } else {
                self.receive()
            }
        }
    }
}
