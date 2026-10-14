# squai

A squad of small AI creatures that live on your macOS desktop. Each one has a
unique skill and helps you with it. The first squad member translates
Japanese <-> English.

Status: pre-alpha scaffold. See `docs/specs/` for the v1 spec and
`docs/research/` for the evidence behind the design.

## Layout

| Path | What |
|---|---|
| `docs/specs/2026-10-14-squai-v1-spec.md` | One-page v1 spec with acceptance criteria |
| `Packages/SquaiCore/` | Pure-Swift library: pet manifest + sprite sheet (Codex-compatible), language detection, `TranslationBackend`/`PetSkill` protocols, Claude Messages API codec. Unit-tested. |
| `App/Squai/` | AppKit menu-bar app: `NSPanel` overlay pet, speech bubble, AX/⌘C selection capture, Apple on-device backend, Keychain, Settings. |
| `App/Squai/Resources/Pets/squai-default/` | Bundled placeholder pet (`pet.json` + 8×9 sprite sheet). |
| `project.yml` | XcodeGen source of truth for `Squai.xcodeproj`. Regenerate with `make gen`. |
| `Scripts/make-placeholder-pet.swift` | Regenerates the placeholder atlas. |

## Build

Requires Xcode 26 and macOS 26 (headless `TranslationSession` API).

```bash
brew install xcodegen
make verify   # swift test (SquaiCore) + xcodebuild Debug
make run      # opens build/DerivedData/.../squai.app
```

Or open `Squai.xcodeproj` and run the `Squai` scheme.

Accessibility permission is required for selection capture. Debug builds are
ad-hoc signed unless you set a team in Xcode (Signing & Capabilities), and macOS
ties the grant to the exact binary, so after each rebuild remove and re-add
squai under System Settings → Privacy & Security → Accessibility. Setting a
team (a free Apple ID "Personal Team" works) gives a stable signature and avoids this.

## Pets

Drop a Codex-style pet folder (`pet.json` + 1536×1872 PNG/WebP atlas, 8 cols × 9
rows of 192×208) into `~/Library/Application Support/squai/pets/<id>/`.
Pets in `~/.codex/pets/` are picked up read-only.
