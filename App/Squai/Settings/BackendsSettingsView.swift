import SwiftUI
import SquaiCore

/// Where the CLIs live, resolved against the login-shell PATH (same lookup the router uses).
struct CLIProbe: Sendable {
    var loginShellPath: String?
    var home: URL

    static func current() async -> CLIProbe {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return CLIProbe(loginShellPath: await CLILocator.loginShellPATH(shell: shell),
                        home: FileManager.default.homeDirectoryForCurrentUser)
    }

    func locate(_ name: String) -> URL? {
        CLILocator().locate(name, loginShellPath: loginShellPath, home: home,
                            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    func childPATH(for cli: URL) -> String {
        CLILocator.childPATH(cliDir: cli.deletingLastPathComponent(), loginShellPath: loginShellPath, home: home)
    }
}

struct BackendsSettingsView: View {
    @State private var apiKey = Keychain.read(service: Keychain.anthropicService) ?? ""
    @State private var keySet = !(Keychain.read(service: Keychain.anthropicService) ?? "").isEmpty
    @State private var keyMessage: String?
    @State private var claudeCLI: URL?
    @State private var codexCLI: URL?
    @State private var checking = false

    var body: some View {
        Form {
            Section("Claude") {
                LabeledContent("Status", value: claudeStatus)
                SecureField("Anthropic API key", text: $apiKey)
                HStack {
                    Button("Save to Keychain", action: saveKey)
                    if let keyMessage { Text(keyMessage).foregroundStyle(.secondary) }
                }
                Text("Used only when the Claude CLI is not available. Model: claude-haiku-5-5.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ChatGPT") {
                LabeledContent("Status", value: chatgptStatus)
                Text("Uses the Codex CLI signed in with ChatGPT. No API key is needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Recheck") { Task { await recheck() } }.disabled(checking)
                    if checking { ProgressView().controlSize(.small) }
                }
            }
        }
        .formStyle(.grouped)
        .task { await recheck() }
    }

    // CLI takes precedence over the key, matching the router order.
    private var claudeStatus: String {
        if checking && claudeCLI == nil { return "Checking…" }
        if let claudeCLI { return "CLI found (\(claudeCLI.path))" }
        return keySet ? "API key set" : "CLI not found"
    }

    private var chatgptStatus: String {
        if checking && codexCLI == nil { return "Checking…" }
        if let codexCLI { return "CLI found (\(codexCLI.path))" }
        return "CLI not found"
    }

    private func recheck() async {
        guard !checking else { return }
        checking = true
        let probe = await CLIProbe.current()
        claudeCLI = probe.locate("claude")
        codexCLI = probe.locate("codex")
        keySet = !(Keychain.read(service: Keychain.anthropicService) ?? "").isEmpty
        checking = false
    }

    private func saveKey() {
        let ok: Bool
        if apiKey.isEmpty {
            ok = Keychain.delete(service: Keychain.anthropicService)
                || Keychain.read(service: Keychain.anthropicService) == nil // nothing to delete is fine
            keyMessage = ok ? "Removed" : "Could not remove the key"
        } else {
            ok = Keychain.write(apiKey, service: Keychain.anthropicService)
            keyMessage = ok ? "Saved" : "Could not save the key"
        }
        keySet = !(Keychain.read(service: Keychain.anthropicService) ?? "").isEmpty
    }
}
