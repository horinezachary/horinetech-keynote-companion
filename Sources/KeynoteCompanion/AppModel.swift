import AppKit
import Foundation
import KeynoteCompanionCore
import ServiceManagement

/// Ties the presentation bridge (Keynote or PowerPoint), the trigger rules and the Companion server together.
/// Lives on the main thread: timers, network callbacks and bridge callbacks all arrive there.
final class AppModel: ObservableObject {
    struct FiredTrigger: Identifiable {
        let id = UUID()
        let date: Date
        let trigger: Trigger
    }

    @Published private(set) var state = SlideState(snapshot: .notRunning)
    @Published private(set) var appError: String?
    /// The app being followed: the one whose slides Companion sees and controls.
    @Published private(set) var activeApp: PresentationApp
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
    @Published var appChoice: AppChoice {
        didSet {
            defaults.set(appChoice.rawValue, forKey: Keys.appChoice)
            poll()
        }
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
    /// Menu UI state: the port field's text before Apply, and whether Settings is expanded.
    @Published var portText = ""
    @Published var showSettings = false

    @Published var openAtLogin: Bool {
        didSet { setOpenAtLogin(openAtLogin) }
    }

    let version: String
    private let defaults = UserDefaults.standard
    private let bridge = PresentationBridge()
    /// Whichever of Keynote and PowerPoint was most recently brought to the front.
    private var lastFrontmost: PresentationApp?
    private var activationObserver: NSObjectProtocol?
    private let server: CompanionServer
    private var engine: TriggerEngine
    private var pollTimer: Timer?
    private var reading = false

    private enum Keys {
        static let port = "port"
        static let allowRemote = "allowRemote"
        static let token = "token"
        static let appChoice = "appChoice"
        static let lastApp = "lastApp"
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
            Keys.appChoice: AppChoice.automatic.rawValue,
            Keys.lastApp: PresentationApp.keynote.rawValue,
            Keys.fireOnBackward: false,
            Keys.fireWhenNotPresenting: false,
        ])
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        port = defaults.integer(forKey: Keys.port)
        allowRemote = defaults.bool(forKey: Keys.allowRemote)
        token = defaults.string(forKey: Keys.token) ?? ""
        appChoice = AppChoice(rawValue: defaults.string(forKey: Keys.appChoice) ?? "") ?? .automatic
        let lastApp = PresentationApp(rawValue: defaults.string(forKey: Keys.lastApp) ?? "") ?? .keynote
        activeApp = appChoice.fixed ?? lastApp
        state = SlideState(snapshot: KeynoteSnapshot(app: activeApp))
        lastFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            .flatMap(PresentationApp.init(bundleID:))
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

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let id = app?.bundleIdentifier, let presentationApp = PresentationApp(bundleID: id) {
                self?.lastFrontmost = presentationApp
            }
        }

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
        bridge.perform(command, on: activeApp) { [weak self] result in
            if case .failure(let error) = result {
                self?.appError = error.localizedDescription
            }
            self?.poll()
        }
    }

    private func poll() {
        guard !reading else { return }
        reading = true
        // Automatic mode reads both apps, to see which one is presenting.
        let apps = appChoice.fixed.map { [$0] } ?? PresentationApp.allCases
        bridge.read(apps) { [weak self] readings, errors in
            guard let self else { return }
            self.reading = false
            let app = SourcePicker.pick(
                self.appChoice, readings: readings, lastFrontmost: self.lastFrontmost,
                current: self.activeApp)
            if app != self.activeApp {
                self.activeApp = app
                self.defaults.set(app.rawValue, forKey: Keys.lastApp)
            }
            if let error = errors[app] {
                self.appError = error.localizedDescription
            } else if let snapshot = readings[app] {
                self.appError = nil
                self.ingest(snapshot)
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
            appError = "Open at login: \(error.localizedDescription)"
        }
    }
}
