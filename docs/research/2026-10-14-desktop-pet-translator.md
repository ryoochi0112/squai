# Research: always-on-display AI pet for JPN<->EN translation (macOS)

Date: 2026-10-14. Sources checked directly unless marked *unverified*.

## 1. What "Codex pet" is (the reference UX)
- Optional animated pixel-art companion floating above all windows, even when the Codex app is minimized. Shows agent status (head-scratch while thinking, speech bubble when done); clicking the bubble opens a reply to the agent. `/pet` toggles, `/hatch` turns an uploaded image into an animated pet. Launched early May 2026. Not available in EEA/UK/CH at launch (secondary coverage).
  - https://www.digitaltrends.com/computing/openais-codex-now-has-a-tiny-ai-pet-that-keeps-you-updated-while-you-code/
  - https://biggo.com/news/202605040025_OpenAI_Codex_desktop_pets
- Custom pet format (third-party docs, *unverified against openai/skills*): one folder under `~/.codex/pets/` with `pet.json` {id, displayName, description, spritesheetPath} + one 1536x1872 PNG/WebP atlas, 8 cols x 9 rows of 192x208 cells, one row per state (idle, running-left/right, waving, jumping, failed, waiting, running, review).
  - https://mcpservers.org/agent-skills/agentspace-so/codex-pet

## 2. Overlay window recipe (Apple DTS-tested on macOS 26)
- `NSPanel` with `.nonactivatingPanel`, `isFloatingPanel = true`, `hidesOnDeactivate = false`.
- `level = .screenSaver` (1000). `.floating`/`.statusBar` sit *below* full-screen content.
- `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]`.
- `NSApp.setActivationPolicy(.accessory)` (or `LSUIElement`) is required to layer above other apps' full-screen Spaces; add a menu-bar status item since Dock icon/menu disappear.
- Show once with `orderFrontRegardless()`; no Space-change observers needed.
  - https://origin-devforums.apple.com/forums/thread/826308
- Transparent pet body: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`; click-through via `ignoresMouseEvents` (toggle dynamically / alpha hit-test so only the sprite is clickable).
  - https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents
  - SwiftUI-in-NSPanel hosting pattern: https://cindori.com/developer/floating-panel
- Transparent SwiftUI windows have redraw quirks; host SwiftUI in `NSHostingView` inside the AppKit panel rather than a pure SwiftUI `Window`. https://developer.apple.com/forums/thread/694837

## 3. Capturing the text to translate (Easydict, 14.9k stars, Swift, pushed 2026-10-13)
Verified from `Easydict/Swift/Utility/EventMonitor/Workflow/SelectionWorkflow.swift`:
1. Accessibility API (`AXSelectedText` of focused element) first.
2. If AX fails/empty → simulated ⌘C ("simulatedShortcutCopy") and read NSPasteboard, then restore clipboard.
3. Further fallback → trigger the frontmost app's menu-bar "Copy" item ("menuBarActionCopy").
Requires Accessibility permission (`AXIsProcessTrusted()`), non-sandboxed build simplifies this. Browsers/Electron report selection inconsistently; test them.
  - https://github.com/tisfeng/Easydict
  - https://github.com/yetone/node-get-selected-text (same AX-then-⌘C strategy, independent confirmation)

## 4. Global hotkey
- `KeyboardShortcuts` (sindresorhus) wraps Carbon `RegisterEventHotKey`, sandbox/App Store safe, ships a SwiftUI recorder. Carbon is deprecated-but-unreplaced; Apple DTS "can't honestly recommend" it but it still works. CGEvent tap needs Input Monitoring and is for intercepting keys, not a single chord.
  - https://developer.apple.com/forums/thread/735223
  - https://swiftpackageregistry.com/sindresorhus/KeyboardShortcuts

## 5. Translation backends
### A. Apple Translation framework (on-device, free, offline)
- macOS 15+. Headless init exists: `TranslationSession(installedSource:target:)` (throws if language pack not installed). Also `prepareTranslation()` to prompt download, `LanguageAvailability().status(from:to:)` → .installed/.supported/.unsupported. All processing on-device. macOS 26 adds `preferredStrategy`.
  - https://developer.apple.com/documentation/translation/translationsession
  - https://developer.apple.com/documentation/translation/languageavailability
- Japanese: Apple Translate app supports ja; framework list must be queried at runtime (`supportedLanguages`). *Unverified for the framework specifically.*
### B. Claude API (quality, nuance, register control, explanations)
From `claude-api` skill (cached 2026-10-06):
- Fast/cheap: `claude-haiku-5-5` $0.10/$0.50 per MTok. Quality: `claude-opus-5-5` $4/$20. Sonnet 5.5 $2/$10.
- Stream (`"stream": true`, SSE) for interactive UI; headers `x-api-key`, `anthropic-version: 2023-06-01`.
- Set `output_config: {effort: "low"}` for a translation popup; read content blocks by `type`.
- `temperature`/`top_p`/`top_k` non-default → 400 on 5.5 models; steer via prompt. Assistant prefill → 400.
- Prompt caching only helps if the fixed prefix ≥512 tokens (Haiku/Sonnet/Opus 5.5); shorter prefixes silently don't cache.
- Structured output: `output_config.format.json_schema` with `additionalProperties:false`, works with streaming.
- Key storage: skill has no Keychain guidance; use macOS Keychain (standard practice, *not from skill*).
### Easydict precedent: supports Apple Translate + OpenAI/Gemini/Claude/DeepSeek/Ollama/Claude Code in one app → multi-engine with on-device default + LLM "explain/nuance" is an established pattern.

## 6. Stack choice
- Native Swift/AppKit gives direct control over window level, Spaces, full-screen auxiliary, click-through, and lowest idle cost. Tauri/Electron can do always-on-top + transparent but macOS window-level behavior is less controllable; Electron idle CPU/memory is materially higher (secondary benchmarks: Tauri ~42 MB vs Electron ~168 MB idle; *unverified method*).
  - https://desktopinsights.com/blog/state-of-desktop-app-development-2026
  - https://tech-insider.org/tauri-vs-electron-2026/
