import SwiftUI
import AppKit

struct Profile: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isActive: Bool
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selected: Profile?
    @Published var editorText = ""
    @Published var status = "Ready"
    @Published var statusIsError = false
    @Published var newProfileName = ""

    private let fm = FileManager.default
    private let claudeDir: URL
    private let activeURL: URL
    private let backupsURL: URL

    init() {
        claudeDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        activeURL = claudeDir.appendingPathComponent("settings.json")
        backupsURL = claudeDir.appendingPathComponent("backups", isDirectory: true)
        reload()
    }

    func reload() {
        do {
            try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            var items: [Profile] = []

            if fm.fileExists(atPath: activeURL.path) {
                items.append(Profile(id: "active", name: "active", url: activeURL, isActive: true))
            }

            let files = try fm.contentsOfDirectory(at: claudeDir, includingPropertiesForKeys: nil)
            for file in files {
                let filename = file.lastPathComponent
                guard filename.hasPrefix("settings.json.") else { continue }
                let name = String(filename.dropFirst("settings.json.".count))
                guard !name.isEmpty, !name.hasSuffix("~"), !name.hasSuffix(".bak") else { continue }
                items.append(Profile(id: name, name: name, url: file, isActive: false))
            }

            profiles = items.sorted { left, right in
                if left.isActive != right.isActive { return left.isActive }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }

            if let selected, let same = profiles.first(where: { $0.url == selected.url }) {
                select(same)
            } else if let first = profiles.first {
                select(first)
            } else {
                selected = nil
                editorText = ""
            }

            setStatus("Loaded \(profiles.count) profile(s)")
        } catch {
            setError("Reload failed: \(error.localizedDescription)")
        }
    }

    func select(_ profile: Profile) {
        selected = profile
        do {
            let rawText = try String(contentsOf: profile.url, encoding: .utf8)
            editorText = jsonTextForEditor(rawText)
            setStatus("Loaded \(profile.name)")
        } catch {
            setError("Read failed: \(error.localizedDescription)")
        }
    }

    func saveSelected() {
        guard let selected else { return }
        do {
            let diskText = try jsonTextForDisk(editorText)
            try backup(url: selected.url, label: selected.url.lastPathComponent)
            try diskText.write(to: selected.url, atomically: true, encoding: .utf8)
            editorText = diskText
            setStatus("Saved \(selected.name)")
            reload()
        } catch {
            setError("Save failed: \(error.localizedDescription)")
        }
    }

    func activateSelected() {
        do {
            let diskText = try jsonTextForDisk(editorText)
            try backup(url: activeURL, label: "settings.json")
            try diskText.write(to: activeURL, atomically: true, encoding: .utf8)
            editorText = diskText
            setStatus("Activated as ~/.claude/settings.json")
            reload()
        } catch {
            setError("Activate failed: \(error.localizedDescription)")
        }
    }

    func saveAsProfile() {
        let name = sanitize(newProfileName)
        guard !name.isEmpty else {
            setError("Profile name is empty")
            return
        }

        do {
            let diskText = try jsonTextForDisk(editorText)
            let target = claudeDir.appendingPathComponent("settings.json.\(name)")
            if fm.fileExists(atPath: target.path) {
                try backup(url: target, label: target.lastPathComponent)
            }
            try diskText.write(to: target, atomically: true, encoding: .utf8)
            editorText = diskText
            newProfileName = ""
            setStatus("Saved profile \(name)")
            reload()
            if let created = profiles.first(where: { $0.name == name }) { select(created) }
        } catch {
            setError("Save as failed: \(error.localizedDescription)")
        }
    }

    func formatJSON() {
        do {
            editorText = try jsonTextForDisk(editorText)
            setStatus("JSON formatted")
        } catch {
            setError("Format failed: invalid JSON")
        }
    }

    func launchClaude() {
        let script = "tmp=$(mktemp /tmp/claude-code.XXXXXX.command); printf '%s\n' 'cd ~ && claude' > \"$tmp\"; chmod +x \"$tmp\"; open -a Terminal \"$tmp\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        do {
            try process.run()
            setStatus("Claude launched in Terminal")
        } catch {
            setError("Launch failed: \(error.localizedDescription)")
        }
    }

    private func validateJSON(_ value: String) throws {
        _ = try JSONSerialization.jsonObject(with: Data(value.utf8))
    }

    private func jsonTextForEditor(_ value: String) -> String {
        (try? jsonTextForDisk(value)) ?? value.replacingOccurrences(of: "\\/", with: "/")
    }

    private func jsonTextForDisk(_ value: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(value.utf8))
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func backup(url: URL, label: String) throws {
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try fm.copyItem(at: url, to: backupsURL.appendingPathComponent("\(label).\(stamp).bak"))
    }

    private func sanitize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_" || char == ".") ? char : "-"
        }.reduce(into: "") { $0.append($1) }
    }


    private func setStatus(_ value: String) {
        status = value
        statusIsError = false
    }

    private func setError(_ value: String) {
        status = value
        statusIsError = true
    }
}

struct ContentView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Profiles")
                        .font(.headline)
                    Spacer()
                    Button { store.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reload")
                }
                .padding(12)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.profiles) { profile in
                            let isSelected = store.selected?.url == profile.url

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(profile.url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.isActive {
                                    Text("active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.select(profile)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(minWidth: 270, idealWidth: 310, maxWidth: 360)
            .background(.regularMaterial)

            Divider()

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.selected?.name ?? "No profile selected")
                            .font(.title3.bold())
                        Text(store.selected?.url.path ?? "~/.claude/settings.json")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Format JSON") { store.formatJSON() }
                    Button("Save") { store.saveSelected() }
                        .keyboardShortcut("s", modifiers: [.command])
                    Button("Activate") { store.activateSelected() }
                        .keyboardShortcut(.return, modifiers: [.command])
                    Button("Launch Claude") { store.launchClaude() }
                }

                JSONFormEditor(jsonText: $store.editorText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("JSON Preview")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(store.editorText.isEmpty ? "{}" : store.editorText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 170)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
                }

                HStack(spacing: 8) {
                    TextField("new profile name", text: $store.newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Button("Save As Profile") { store.saveAsProfile() }
                    Spacer()
                    Text(store.status)
                        .font(.caption)
                        .foregroundStyle(store.statusIsError ? .red : .secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 1050, minHeight: 680)
    }
}

@main
struct ClaudeSettingsManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
