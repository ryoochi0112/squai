import AppKit
import SquaiCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let onSettings: () -> Void
    private let onReloadSquad: () -> Void
    private let onPickPet: (InstalledPet) -> Void
    private let pets: () -> [InstalledPet]
    private var currentPets: [InstalledPet] = []

    init(onSettings: @escaping () -> Void,
         onReloadSquad: @escaping () -> Void,
         onPickPet: @escaping (InstalledPet) -> Void,
         pets: @escaping () -> [InstalledPet]) {
        self.onSettings = onSettings
        self.onReloadSquad = onReloadSquad
        self.onPickPet = onPickPet
        self.pets = pets
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "squai")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let petsMenu = NSMenu()
        currentPets = pets()
        for (i, pet) in currentPets.enumerated() {
            let mi = NSMenuItem(title: pet.manifest.displayName, action: #selector(pickPet(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            mi.state = pet.manifest.id == Preferences.selectedPetID ? .on : .off
            petsMenu.addItem(mi)
        }
        if currentPets.isEmpty { petsMenu.addItem(withTitle: "No pets found", action: nil, keyEquivalent: "") }
        petsMenu.addItem(.separator())
        petsMenu.addItem(withTitle: "Open Pets Folder", action: #selector(openPetsFolder), keyEquivalent: "").target = self
        let petsItem = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        petsItem.submenu = petsMenu
        menu.addItem(petsItem)

        menu.addItem(withTitle: "Reload Squad", action: #selector(reloadSquad), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit squai", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func settings() { onSettings() }
    @objc private func reloadSquad() { onReloadSquad() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func pickPet(_ sender: NSMenuItem) {
        guard currentPets.indices.contains(sender.tag) else { return }
        onPickPet(currentPets[sender.tag])
    }
    @objc private func openPetsFolder() {
        let url = PetLibrary.defaultSearchPaths[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
