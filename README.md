# squai

squai puts a small squad of AI creatures on your macOS desktop. Each creature has one job that you define in plain language. Examples are "translate to natural English", "make this polite Japanese", and "summarize in 3 bullets".

Select text in any app, then click a creature. The creature runs its job on your text and shows the result in a bubble next to it. You can copy the result or replace the selected text with it.

squai uses the Claude or ChatGPT subscription that you already pay for. The squad is always on your display, but the AI work runs in the cloud.

Status: v2 is built and waiting for manual checks. See `HANDOFF.md`.

## What you need

- macOS 26.
- For Claude members: the `claude` CLI, logged in. Run `claude` once in Terminal to log in.
- For ChatGPT members: the `codex` CLI, logged in. Run `codex login` once in Terminal.
- Optional fallback for Claude members only: a Claude API key. Enter it in Settings → Backends. squai stores it in Keychain, service `com.squai.anthropic`.
- ChatGPT has no API key fallback in v2.

squai tries the `claude` CLI first. If the CLI is missing, it uses the API key. If neither exists, the bubble says "Claude is not set up" and offers a button to open Settings.

## Build and run

Requires Xcode 26 and macOS 26.

```bash
brew install xcodegen
make verify   # swift test (SquaiCore) + xcodebuild Debug
make run      # build, then open build/DerivedData/Build/Products/Debug/squai.app
```

Other commands:

- `make gen` regenerates `Squai.xcodeproj` from `project.yml`. Run it after you edit `project.yml`.
- `make placeholder-pet` regenerates the placeholder sprite sheet of the bundled default look.

You can also open `Squai.xcodeproj` and run the `Squai` scheme.

### Accessibility permission

squai needs Accessibility permission to read the selected text. Debug builds are ad-hoc signed. macOS ties the permission to the exact binary, so the permission stops working after every rebuild.

After each rebuild, do these steps:

1. Open System Settings → Privacy & Security → Accessibility.
2. Remove squai from the list.
3. Add squai again.

A stable signing team in Xcode (Signing & Capabilities) avoids this. A free Apple ID "Personal Team" works.

## Your squad

On first launch the squad is empty. squai shows no creature and opens Settings → Squad on the "Create member" form.

Fill in a name, a prompt, a backend (Claude or ChatGPT), a look, an optional hotkey, and the visible switch. Press Save. The creature appears on your desktop.

You can also create a member by hand, as described below.

### Member folder

One folder is one member. Put the folder in:

```
~/Library/Application Support/squai/pets/<id>/
```

The folder name is the member id. The folder holds three things:

| File | What |
|---|---|
| `pet.json` | Look manifest (Codex-compatible). |
| Sprite sheet | PNG or WebP, 1536×1872 pixels. It has 8 columns and 9 rows of cells. Each cell is 192×208 pixels. |
| `skill.json` | The job of the member. |

`skill.json` has five fields:

| Field | Meaning |
|---|---|
| `name` | Display name. |
| `prompt` | The instruction. squai sends `prompt`, a blank line, then the selected text. |
| `backend` | `claude` or `chatgpt`. |
| `hotkey` | Optional, for example `opt+cmd+p`. |
| `visible` | `true` shows the creature. `false` hides it. |

Example:

```json
{ "name": "Polite", "prompt": "Rewrite in polite business Japanese. Output only the rewritten text.",
  "backend": "claude", "hotkey": "opt+cmd+p", "visible": true }
```

The file is the source of truth. After you edit it on disk, choose Settings → Squad → Reload. Unknown keys are ignored.

To share a member, zip the folder and send it. The receiver unzips it into the same `pets/` folder, and the member appears.

### Looks

A look is a folder with `pet.json` and a sprite sheet, but no `skill.json`. squai finds looks in three places:

- `~/Library/Application Support/squai/looks/` (your own looks, including generated ones).
- The looks bundled in the app (`App/Squai/Resources/Pets/`).
- `~/.codex/pets/`. squai only reads this folder. When you pick one of these looks, squai copies it into your squai folder.

### Hotkeys

A hotkey has one key and one or more modifier keys. The modifiers are `ctrl`, `opt`, `shift`, and `cmd`. The key is `a`-`z`, `0`-`9`, `f1`-`f12`, or `space`. Two members cannot share a hotkey.

A hidden member (`visible` is `false`) runs only by hotkey, so it must have one.

### Use a creature

- Left-click a creature to run it on the selected text.
- Right-click a creature to show its last result. Right-click never runs the job.
- In the result bubble, Copy puts the result on the clipboard. Replace pastes the result over the original selection and then restores your previous clipboard. If the paste cannot be delivered, the bubble says "Copied — could not replace" and the result stays on the clipboard.

## Generate a look

In the create form, "Generate look" makes a new look from a text description. It needs all of these:

- The `codex` CLI, logged in with ChatGPT (`codex login`).
- The `hatch-pet` Codex skill in `~/.codex/skills/hatch-pet`.
- Python 3 with Pillow. Install it with `python3 -m pip install --user pillow`.

Generation takes 10 to 20 minutes and uses your ChatGPT quota. It runs in the background in `~/Library/Application Support/squai/hatch/<run-id>/`. On success, the new look appears in the look picker under `~/Library/Application Support/squai/looks/<id>/`.

If something is missing, the form says which piece. You can also make a look in Codex with `/hatch`. It appears in the look picker automatically.

## Layout

| Path | What |
|---|---|
| `docs/specs/2026-10-14-squai-v2-squad-spec.md` | v2 spec with acceptance criteria |
| `docs/specs/2026-10-14-squai-v2-design.md` | v2 engineering design |
| `Packages/SquaiCore/` | Pure-Swift library, unit-tested. It holds the member and look scan, `skill.json`, hotkeys, CLI runner, backend router, and sprite sheet validator. |
| `App/Squai/` | AppKit menu-bar app: overlay pets, bubbles, selection capture, Settings, Keychain. |
| `App/Squai/Resources/Pets/` | Bundled looks. |
| `project.yml` | XcodeGen source of truth for `Squai.xcodeproj`. |
| `Scripts/make-placeholder-pet.swift` | Regenerates the placeholder sprite sheet. |
