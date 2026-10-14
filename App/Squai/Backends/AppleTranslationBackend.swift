import Foundation
import Translation
import SquaiCore

/// On-device translation via Apple's Translation framework. Headless `TranslationSession(installedSource:target:)` is macOS 26+;
/// macOS 15 would need the SwiftUI `.translationTask` modifier on a hosted view instead.
/// `TranslationSession(installedSource:target:)` throws when the language pack is missing;
/// we map that to `TranslationError.languagePackMissing` so the UI can offer a download.
struct AppleTranslationBackend: TranslationBackend {
    let id = "apple"

    func translate(_ text: String, direction: LanguageDirection) async throws -> TranslationResult {
        let source = Locale.Language(identifier: direction.source)
        let target = Locale.Language(identifier: direction.target)

        let status = await LanguageAvailability().status(from: source, to: target)
        switch status {
        case .installed: break
        case .supported: throw TranslationError.languagePackMissing(source: direction.source, target: direction.target)
        case .unsupported: throw TranslationError.unsupported(source: direction.source, target: direction.target)
        @unknown default: throw TranslationError.unsupported(source: direction.source, target: direction.target)
        }

        let session: TranslationSession
        do {
            session = try TranslationSession(installedSource: source, target: target)
        } catch {
            throw TranslationError.languagePackMissing(source: direction.source, target: direction.target)
        }
        let response: TranslationSession.Response
        do {
            response = try await session.translate(text)
        } catch {
            // Observed on macOS 26.5: status can read `.installed` while the session still reports notInstalled.
            NSLog("squai: apple translate failed: %@", String(describing: error))
            if String(describing: error).contains("notInstalled") {
                throw TranslationError.languagePackMissing(source: direction.source, target: direction.target)
            }
            throw error
        }
        let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw TranslationError.empty }
        return TranslationResult(text: out, note: nil, backend: id)
    }

    /// Best-effort: a headless session cannot show the download sheet, so open the
    /// system Translation settings where the user can download the pack.
    @MainActor
    static func prepare(source: String, target: String) async {
        // TODO(v1): host a hidden SwiftUI view with `.translationTask` + `prepareTranslation()` to show the download sheet in-app.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

import AppKit
