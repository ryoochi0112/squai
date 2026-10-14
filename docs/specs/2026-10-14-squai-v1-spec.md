# squai v1 — spec (one page)

Date: 2026-10-14. Status: draft for build. Evidence: `docs/research/2026-10-14-desktop-pet-translator.md`.

## Goal
A menu-bar macOS app that shows one pixel-art pet floating over every window and Space. The v1 pet has one skill: translate selected text between Japanese and English, on-device by default, with Claude Haiku on demand. The pet art format is byte-compatible with Codex pets so existing pets drop in.

## Non-goals (v1)
No App Store sandbox, no `/hatch` image-to-sprite generation, no chat with the pet, no languages other than ja/en, no cloud sync, no Windows/Linux.

## User flow
1. Launch → menu-bar icon only (no Dock icon). First run asks for Accessibility permission and offers to download the Apple ja/en language pack.
2. User selects text in any app and presses the hotkey (default ⌥⌘T).
3. Pet plays its `running` row, then shows a speech bubble with the translation. Direction is auto-detected: text containing kana or CJK → en, otherwise → ja.
4. Bubble has two actions: **Copy** and **Ask Claude** (re-translates with `claude-haiku-5-5`, adds one line of nuance/register note). Esc or a click outside closes it. Bubble auto-hides after 12 s.
5. Pet is draggable; position persists. Clicking the pet opens the bubble with the last result. The pet never steals focus.

## Architecture
| Layer | Decision |
|---|---|
| App shell | AppKit + SwiftUI views. `NSApp.setActivationPolicy(.accessory)`, `LSUIElement = YES`, `NSStatusItem` menu. |
| Overlay | `NSPanel(.nonactivatingPanel)`, `isFloatingPanel`, `hidesOnDeactivate = false`, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]`, transparent/non-opaque/no shadow, `orderFrontRegardless()`. SwiftUI hosted in `NSHostingView`. Hit-testing limited to the sprite alpha. |
| Pet format | Folder with `pet.json` `{id, displayName, description, spritesheetPath}` + one 1536×1872 PNG/WebP atlas, 8 cols × 9 rows of 192×208 cells. Row order: idle, running-left, running-right, waving, jumping, failed, waiting, running, review. Search paths: `~/Library/Application Support/squai/pets/`, then `~/.codex/pets/` (read-only). Bundled default pet at `Resources/Pets/squai-default/`. |
| Text capture | AX `kAXSelectedTextAttribute` on focused element → fallback simulated ⌘C with clipboard restore (Easydict strategy). Needs `AXIsProcessTrusted()`; non-sandboxed Developer ID build. |
| Hotkey | `KeyboardShortcuts` (sindresorhus) SPM package; recorder in Settings. |
| Translation | Protocol `TranslationBackend { translate(text, from, to) async throws -> Translation }`. `AppleTranslationBackend` (headless `TranslationSession(installedSource:target:)`, **macOS 26+ only**; availability checked via `LanguageAvailability`). `ClaudeBackend` (Messages API, `claude-haiku-5-5`, non-streaming v1, `output_config.effort = low`, no `temperature`). API key in Keychain (`kSecClassGenericPassword`, service `com.squai.anthropic`). |
| Skills | `protocol PetSkill { id, displayName, hotkeyName, run(input: SkillInput) async throws -> SkillOutput }`. `SkillRegistry` holds skills; `TranslateSkill` is the only v1 implementation. Adding a skill = one type + one registry line; no UI changes. |
| Settings | SwiftUI window: hotkey, pet picker, backend default, Claude key, launch at login (`SMAppService`). |

## Acceptance criteria
- [ ] AC1 Pet is visible above a full-screen Safari window and a full-screen Terminal on a second Space without any Space-change observer.
- [ ] AC2 Clicking through the transparent area of the panel reaches the window below; clicking the sprite does not activate squai.
- [ ] AC3 Hotkey on selected text in Safari, VS Code, and Slack yields a bubble within 1.5 s on-device (language pack installed). Clipboard contents are unchanged afterwards.
- [ ] AC4 Direction auto-detect: `こんにちは` → English; `hello` → Japanese.
- [ ] AC5 With no language pack installed, bubble shows a one-click "Download ja/en" action instead of an error.
- [ ] AC6 "Ask Claude" with a valid key returns a translation plus a ≤1-line note; with no key it opens Settings. Key is never written to disk outside Keychain.
- [ ] AC7 A pet folder copied from `~/.codex/pets/<x>/` appears in the pet picker and animates all 9 rows at 8 fps without edits.
- [ ] AC8 Idle CPU < 1 % and RSS < 60 MB after 10 min idle (Activity Monitor).
- [ ] AC9 `swift test` passes for: direction detection, pet.json decoding, sprite-sheet slicing (72 cells), Claude request/response codec.
- [ ] AC10 Quitting from the menu removes the panel and status item; relaunch restores pet position.

## Risks / open items
- Headless `TranslationSession(installedSource:target:)` is macOS 26+, not 15+ as the research note said (found at first build). Deployment target is therefore macOS 26.0. Supporting macOS 15 would need a hidden SwiftUI view with `.translationTask`.
- Apple Translation framework ja support is unverified at the framework level; AC5 covers the failure path.
- Electron apps and some browsers report AX selection inconsistently; AC3 is the gate, ⌘C fallback is the mitigation.
- Carbon hotkeys are deprecated-but-working; keep the hotkey layer behind one type so it can be swapped.
- Codex pet row semantics are from third-party docs; treat row order as a config constant.

## Assumptions made (not in the brief)
Default hotkey ⌥⌘T; 8 fps sprite playback; bubble auto-hide 12 s; macOS 26.0 deployment target (headless Translation API); bundle id `com.squai.app`; non-streaming Claude call in v1.
