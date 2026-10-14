import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var apiKey = Keychain.read(service: Keychain.anthropicService) ?? ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var saved = false

    var body: some View {
        Form {
            Section("Claude") {
                SecureField("Anthropic API key", text: $apiKey)
                HStack {
                    Button("Save to Keychain") {
                        saved = apiKey.isEmpty
                            ? Keychain.delete(service: Keychain.anthropicService)
                            : Keychain.write(apiKey, service: Keychain.anthropicService)
                    }
                    if saved { Text("Saved").foregroundStyle(.secondary) }
                }
                Text("Used only when the Claude CLI is not available. Model: claude-haiku-5-5.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Button("Grant Accessibility access…") { SelectionCapture.requestAccessibilityIfNeeded() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 360)
    }
}
