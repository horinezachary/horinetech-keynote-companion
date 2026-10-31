import AppKit
import KeynoteCompanionCore
import SwiftUI

struct MenuView: View {
    // UI state lives on the model, not in @State: on the macOS 27 SDK @State is a macro whose
    // plugin ships only with Xcode, so a Command Line Tools-only build would fail.
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            slideSection
            Divider()
            controls
            Divider()
            companionSection
            if !model.recentTriggers.isEmpty {
                Divider()
                triggersSection
            }
            Divider()
            DisclosureGroup("Settings", isExpanded: $model.showSettings) { settings }
            Divider()
            HStack {
                Text("Keynote Companion \(model.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { model.portText = String(model.port) }
    }

    // MARK: Sections

    @ViewBuilder private var slideSection: some View {
        let s = model.state
        VStack(alignment: .leading, spacing: 6) {
            if !s.keynoteRunning {
                Text("Keynote is not running").font(.headline)
            } else if s.document.isEmpty {
                Text("No presentation open").font(.headline)
            } else {
                HStack {
                    Text(s.slide > 0 ? "Slide \(s.slide) of \(s.slideCount)" : "\(s.slideCount) slides")
                        .font(.headline)
                    Spacer()
                    Text(s.playing ? "Presenting" : "Editing")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(s.playing ? Color.green.opacity(0.25) : Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(s.document).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !s.labels.isEmpty {
                    LabelChips(labels: s.labels)
                }
                if !s.notesPlain.isEmpty {
                    Text(s.notesPlain)
                        .font(.callout)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
            }
            if let error = model.keynoteError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button { model.send(.previous) } label: { Image(systemName: "backward.fill") }
                .help("Previous")
            Button { model.send(.next) } label: { Image(systemName: "forward.fill") }
                .help("Next")
            Spacer()
            if model.state.playing {
                Button("Stop") { model.send(.stop) }
            } else {
                Button("Play from current") { model.send(.start(.current)) }
                    .disabled(!model.state.keynoteRunning || model.state.document.isEmpty)
            }
        }
    }

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Companion").font(.headline)
            let addresses = model.allowRemote ? NetworkInfo.ipv4Addresses() : []
            ForEach(["127.0.0.1"] + addresses, id: \.self) { ip in
                Text("\(ip):\(String(model.port))")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text(model.serverStatus).font(.caption).foregroundStyle(.secondary)
            Text(model.clientCount == 1 ? "Connected: 1 client" : "Connected: \(model.clientCount) clients")
                .font(.caption)
                .foregroundStyle(model.clientCount > 0 ? Color.green : Color.secondary)
        }
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent labels").font(.headline)
            ForEach(model.recentTriggers) { fired in
                HStack {
                    Text(fired.trigger.label).font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("slide \(fired.trigger.slide)").font(.caption).foregroundStyle(.secondary)
                    Text(fired.date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Port")
                TextField("7878", text: $model.portText)
                    .frame(width: 70)
                    .onSubmit(applyPort)
                Button("Apply", action: applyPort)
                    .disabled(Int(model.portText) == model.port)
            }
            Toggle("Allow other computers to connect", isOn: $model.allowRemote)
            HStack {
                Text("Shared token")
                SecureField("none", text: $model.token)
            }
            Toggle("Fire labels when going back a slide", isOn: $model.fireOnBackward)
            Toggle("Fire labels when not presenting", isOn: $model.fireWhenNotPresenting)
            Toggle("Open at login", isOn: $model.openAtLogin)
        }
        .padding(.top, 6)
    }

    private func applyPort() {
        guard let p = Int(model.portText), (1...65535).contains(p) else {
            model.portText = String(model.port)
            return
        }
        model.port = p
        model.restartServer()
    }
}

private struct LabelChips: View {
    let labels: [String]

    var body: some View {
        // Wraps onto a few lines without needing a custom layout.
        Text(labels.map { "[\($0)]" }.joined(separator: "  "))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}
