import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection", default: .init(.t, modifiers: [.option, .command]))
    static let translateSelectionPremium = Self("translateSelectionPremium", default: .init(.t, modifiers: [.option, .command, .shift]))
}
