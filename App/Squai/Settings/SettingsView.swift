import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: MemberStore
    let onReload: () -> Void

    var body: some View {
        TabView {
            SquadSettingsView(store: store, onReload: onReload)
                .tabItem { Label("Squad", systemImage: "person.3") }
            BackendsSettingsView()
                .tabItem { Label("Backends", systemImage: "key") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 760, height: 620)
    }
}

private struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
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
    }
}
