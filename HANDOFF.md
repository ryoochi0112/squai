# HANDOFF — squai (2026-10-14)

## Verified state

Anchored to `809cfe3` on `fix/error-diagnostics`, tree clean except the untracked root
`RESEARCH-desktop-pet-translator.md` (byte-identical duplicate of the docs/research file; not mine to delete).

DONE (verified):
- v1 spec + scaffold merged to `main` as PR ryoochi0112/squai#1 (`129d2a6`).
- `make verify` on `809cfe3`: 20 SquaiCore tests pass, Debug build succeeds.
- App launches as a menu-bar accessory; placeholder pet renders above the Dock (screenshot checked).
- Apple ja/en language pack: user installed it this session. Before install, a standalone probe
  showed `LanguageAvailability` = `.supported` (not installed) and `TranslationSession.translate`
  threw `notInstalled`. Not re-probed after install.
- Headless `TranslationSession(installedSource:target:)` is macOS 26+ → deployment target is 26.0.
- This Mac has no code-signing identity and the user has no Apple ID. Debug builds are ad-hoc
  signed, so the Accessibility grant dies on every rebuild; user must remove/re-add squai in
  System Settings → Privacy & Security → Accessibility after each ⌘R.

未検証 (unverified):
- Commit `809cfe3` capture rewrite (modifier-release wait, `.cgSessionEventTap`, Edit ▸ Copy
  menu fallback, per-stage diagnostics). Compiles; never exercised against Safari.
- AC1–AC8 and AC10 in the spec are all manual and untested.

作業中 (in flight):
- Selection capture in Safari fails. Last user-observed result (before `809cfe3`): Accessibility
  guard passed, then "No selected text was found" → both AX read and synthetic ⌘C returned empty.
  Leading hypothesis: ⌥ still held at key-up merged into ⌥⌘C. `809cfe3` addresses that plus adds
  a menu-item fallback. Needs the user to rebuild, re-grant Accessibility, retry, and paste the
  bubble's `Diagnostics:` line.

## Open decisions

1. New initiative from the user: "make this repo enable users to build the on-device AI squad."
   Not started. Needs a grill (one question at a time) before any spec: who are "users"
   (end users dropping pet folders vs developers adding skills), what "build" means (sprite +
   skill definition via files? a GUI? a CLI?), and whether "on-device" rules out the Claude
   backend or only sets the default. Pointer: `docs/specs/2026-10-14-squai-v1-spec.md` §Skills
   describes the current `PetSkill` protocol; `Packages/SquaiCore/Sources/SquaiCore/Skills.swift`.
2. Yes/no: merge `fix/error-diagnostics` even if capture is still failing? (It is strictly
   better diagnostics than `main`.) Recommended: yes, after one manual retry.
3. Yes/no: delete the untracked root `RESEARCH-desktop-pet-translator.md` duplicate.

## Environment

```bash
cd /Users/ryoochi/squai
git checkout fix/error-diagnostics
make verify          # swift test (Packages/SquaiCore) + xcodebuild Debug, exit 0 expected
make run             # or open Squai.xcodeproj and run scheme Squai
```

- Toolchain: Xcode 26.6, Swift 6.3, macOS 26.5.1, xcodegen 2.46 (Homebrew). `make gen` after editing `project.yml`.
- No env vars required. Claude key, if used, lives in Keychain service `com.squai.anthropic` (set via Settings window).
- rstaff completion gate blocks session stop until a plain, unredirected `make verify` exits 0 on the current tree.

## Next actions

1. User: ⌘R in Xcode → re-add squai in Accessibility → select text in Safari → ⌥⌘T, release all keys → paste the
   `Diagnostics:` line from the bubble (it is selectable). If a Japanese bubble appears, capture works.
2. Fix whatever stage the diagnostics name (`ax=…` → AX path; `pb changed=false` → synthetic ⌘C not delivered;
   `menu: Copy item not found` → menu walk in `SelectionCapture.findMenuItem`).
3. Commit → push → open PR for `fix/error-diagnostics`; tick AC3/AC4/AC5 in the spec once seen.
4. Start the "users build their own squad" initiative in a fresh session with a grill, then `/rstaff-pm:spec`.
5. Remaining v1 items from the spec: in-app language-pack download sheet (hidden SwiftUI `.translationTask`
   view), real pixel art for `App/Squai/Resources/Pets/squai-default/`.

## Pointers

- Spec: `docs/specs/2026-10-14-squai-v1-spec.md`
- Research: `docs/research/2026-10-14-desktop-pet-translator.md`
- Capture: `App/Squai/Capture/SelectionCapture.swift`; error text: `AppDelegate.describe(_:)`
- On-device backend: `App/Squai/Backends/AppleTranslationBackend.swift`
- Repo: https://github.com/ryoochi0112/squai (public); PR #1 merged
