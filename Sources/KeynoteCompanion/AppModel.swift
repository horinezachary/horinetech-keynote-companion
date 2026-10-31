import Foundation
import KeynoteCompanionCore
import ServiceManagement

/// Ties the Keynote bridge, the trigger rules and the Companion server together.
/// Lives on the main thread: timers, network callbacks and bridge callbacks all arrive there.
final class AppModel: ObservableObject {
    struct FiredTrigger: Identifiable {
        let id = UUID()
        let date: Date
        let trigger: Trigger
    }

    @Published private(set) var state = SlideState(snapshot: .notRunning)
    @Published private(set) var keynoteError: String?
    @Published private(set) var clientCount = 0
    @Published private(set) var serverStatus = "Starting"
    @Published private(set) var recentTriggers: [FiredTrigger] = []

    @Published var port: Int {
        didSet { defaults.set(port, forKey: Keys.port) }
    }
    @Published var allowRemote: Bool {
        didSet {
            defaults.set(allowRemote, forKey: Keys.allowRemote)
            restartServer()
        }
    }
    @Published var token: String {
        didSet { defaults.set(token, forKey: Keys.token) }
    }
    @Published var fireOnBackward: Bool {
        didSet {
            defaults.set(fireOnBackward, forKey: Keys.fireOnBackward)
            engine.options.fireOnBackward = fireOnBackward
        }
    }
    @Published var fireWhenNotPresenting: Bool {
        didSet {
            defaults.set(fireWhenNotPresenting, forKey: Keys.fireWhenNotPresenting)
            engine.options.fireWhenNotPresenting = fireWhenNotPresenting
        }
    }
    @Published var openAtLogin: Bool {
        didSet { setOpenAtLogin(openAtLogin) }
    }

    let version: String
    private let defaults = UserDefaults.standard
    private let bridge = KeynoteBridge()
    private let server: CompanionServer
    private var engine: TriggerEngine
    private var pollTimer: Timer?
    private var reading = false

    private enum Keys {
        static let port = "port"
        static let allowRemote = "allowRemote"
        static let token = "token"
        static let fireOnBackward = "fireOnBackward"
        static let fireWhenNotPresenting = "fireWhenNotPresenting"
    }

    /// About 7 readings a second.
    static let pollInterval: TimeInterval = 0.15

    init() {
        defaults.register(defaults: [
            Keys.port: Int(defaultPort),
            Keys.allowRemote: true,
            Keys.token: "",
            Keys.fireOnBackward: false,
            Keys.fireWhenNotPresenting: false,
        ])
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        port = defaults.integer(forKey: Keys.port)
        allowRemote = defaults.bool(forKey: Keys.allowRemote)
        token = defaults.string(forKey: Keys.token) ?? ""
        fireOnBackward = defaults.bool(forKey: Keys.fireOnBackward)
        fireWhenNotPresenting = defaults.bool(forKey: Keys.fireWhenNotPresenting)
        openAtLogin = SMAppService.mainApp.status == .enabled
        engine = TriggerEngine(
            options: TriggerOptions(
                fireOnBackward: defaults.bool(forKey: Keys.fireOnBackward),
                fireWhenNotPresenting: defaults.bool(forKey: Keys.fireWhenNotPresenting)))
        server = CompanionServer(appVersion: version)

        server.currentState = { [weak self] in self?.state }
        server.token = { [weak self] in self?.token ?? "" }
        server.onClientsChanged = { [weak self] n in self?.clientCount = n }
        server.onStatus = { [weak self] s in self?.serverStatus = s }
        server.onCommand = { [weak self] command, client in
            self?.handle(command, from: client)
        }
        restartServer()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)  // keep polling while the menu is open
        pollTimer = timer
        poll()
    }

    func restartServer() {
        let clamped = UInt16(clamping: max(port, 0))
        server.start(.init(port: clamped, allowRemote: allowRemote))
    }

    /// Commands from the menu go through the same path as Companion's.
    func send(_ command: Command) {
        handle(command, from: nil)
    }

    private func handle(_ command: Command, from client: ClientConnection?) {
        if command == .refresh {
            client?.send(WireCodec.line(state))
            return
        }
        bridge.perform(command) { [weak self] result in
            if case .failure(let error) = result {
                self?.keynoteError = error.localizedDescription
            }
            self?.poll()
        }
    }

    private func poll() {
        guard !reading else { return }
        reading = true
        bridge.read { [weak self] result in
            guard let self else { return }
            self.reading = false
            switch result {
            case .success(let snapshot):
                self.keynoteError = nil
                self.ingest(snapshot)
            case .failure(let error):
                self.keynoteError = error.localizedDescription
            }
        }
    }

    private func ingest(_ snapshot: KeynoteSnapshot) {
        let update = engine.ingest(snapshot)
        if let newState = update.state {
            state = newState
            server.broadcast(newState)
        }
        guard !update.triggers.isEmpty else { return }
        let now = Date()
        for trigger in update.triggers {
            server.broadcast(trigger)
        }
        recentTriggers = (update.triggers.reversed().map { FiredTrigger(date: now, trigger: $0) }
            + recentTriggers).prefix(8).map { $0 }
    }

    private func setOpenAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            keynoteError = "Open at login: \(error.localizedDescription)"
        }
    }
}
