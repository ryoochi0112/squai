# HANDOFF — squai v2 (2026-10-14)

## State

v2 is merged to `main` (PR #3, `3b99648`). Tasks T1 to T10 and the review fixes (`620522b`) are in.
`make verify` is the gate (SquaiCore tests plus the Debug build).

Built in v2: member folders (`pet.json`, sprite sheet, `skill.json`), the Squad editor in Settings,
click and hotkey runs through the `claude` and `codex` CLIs, the Claude API key fallback,
Copy and Replace, multi-pet overlay, Codex look import, and look generation with `hatch-pet`.
The v1 translator and the Apple Translation backend are removed.

Manual ACs 1 to 4 passed in the Debug app on 2026-10-15. AC4 passed in Safari, VS Code and Slack,
so the capture rewrite `ad00544` works there. The other manual ACs are not run yet.

## Manual AC checklist (ACs 1 to 13 and 15)

Run these in the Debug app (`make run`). After every rebuild, remove and re-add squai in
System Settings → Privacy & Security → Accessibility. Tick each AC in
`docs/specs/2026-10-14-squai-v2-squad-spec.md` when it passes.

Start with AC4 in Safari, to confirm the capture rewrite before you judge anything else.

| AC | How to test | Run? |
|---|---|---|
| 1 | Delete `~/Library/Application Support/squai/`. Launch. No pet appears, and Settings opens on the Create member form. | Pass (2026-10-15) |
| 2 | Fill the form (name, prompt, backend, look, hotkey, visible) and Save. The pet appears within 1 s. Check `pets/<id>/` has `pet.json`, the sheet, and `skill.json` with the form values. | Pass (2026-10-15) |
| 3 | Prompt "Reply with exactly the word PING"; run it, bubble is `PING`. Edit `skill.json` to PONG, choose Reload. The GUI shows PONG and the next bubble is `PONG`. Delete the folder and Reload; pet and row disappear. | Pass (2026-10-15) |
| 4 | Select text in Safari, VS Code, and Slack; left-click a pet. The bubble shows within 10 s (Claude) or 20 s (ChatGPT). The source app keeps focus and selection. | Pass (2026-10-15): Safari, VS Code, Slack |
| 5 | Set a hotkey on a member, also on a hidden one; it runs as in AC4. Saving a second member with the same hotkey shows an inline error. | No |
| 6 | Prompt "Echo the input exactly". Right-click first: "No result yet". Select `alpha`, left-click: `alpha`. Select `beta`, right-click: still `alpha`. Left-click: `beta`. | No |
| 7 | Confirm no Keychain item `com.squai.anthropic`. Put a shim `claude` first on `PATH` that logs args and stdin to `/tmp/squai-cli.log` and prints `SHIM-OK`. Run a Claude member: body `SHIM-OK`, log has `-p`. Repeat with a shim `codex` (log has `exec`). Rename the shim away; the Backends status flips to "CLI not found". | No |
| 8 | No CLI plus a key in Keychain: the Claude run works. No CLI and no key: "Claude is not set up" with a button to Settings. ChatGPT without `codex`: "ChatGPT is not set up". Run `grep -r` over Application Support and Preferences: no key found. | No |
| 9 | In TextEdit, press Replace: text is replaced and the clipboard is restored. Run again, click another app, right-click the pet to re-show the result, press Replace: "Copied — could not replace" and the clipboard holds the body. | No |
| 10 | Show three members. Drag each, quit, relaunch: positions are kept. Turn `visible` off for one: only that pet disappears. | No |
| 11 | Put a look-only folder in `~/.codex/pets/`. It appears in the look picker but not on the desktop. Choose it: it is copied into squai's folder, `skill.json` is written there, and `~/.codex/pets/` gains no file. | No |
| 12 | Zip a member folder, delete the folder, unzip it into `pets/`. The member returns with the same fields and no GUI step. | No |
| 13 | With `codex` logged in, `hatch-pet` installed, and Pillow, press Generate look. The form shows "Generating…" and Cancel. The result is in `looks/<id>/`; `sips -g pixelWidth -g pixelHeight` reports 1536×1872. Preview rows lists all 9 row names. Without `codex` or the skill, inline text names the missing piece with no dialog. `~/.codex/pets/` gains no file. | No |
| 15 | Member prompt "Translate between Japanese and English; detect the direction; output only the translation". `こんにちは` gives English; `hello` gives Japanese. | No |

AC14 (unit tests) is covered by `make verify`.

## Open items

- v2.1: ChatGPT API key fallback (v2 ChatGPT uses `codex exec` only).
- v2.1: per-member model (v2 fixes `--model haiku` for Claude).
- Backlog: symlink TOCTOU hardening for member folders is out of the threat model.
- Known gap: Replace into a read-only field fails silently. squai cannot detect it.
- Risk: `hatch-pet` is a Codex skill that squai does not control. squai validates its output.

## Environment

```bash
cd /Users/ryoochi/squai
make verify          # swift test (Packages/SquaiCore) + xcodebuild Debug, exit 0 expected
make run             # build and open the app
```

- Toolchain: Xcode 26.6, Swift 6.3, macOS 26.5.1, xcodegen 2.46. Run `make gen` after you edit `project.yml`.
- Debug builds are ad-hoc signed, so the Accessibility grant dies on every rebuild.
- The Claude API key lives only in Keychain, service `com.squai.anthropic`.
- CI: `.github/workflows/verify.yml` runs `make verify` on `macos-26` (job `verify`). Merge is a human action.

## Next actions

1. Run the remaining manual ACs above (5 to 13, 15). The squad is empty again after AC3.

## Pointers

- v2 spec: `docs/specs/2026-10-14-squai-v2-squad-spec.md`
- v2 design: `docs/specs/2026-10-14-squai-v2-design.md`
- Capture: `App/Squai/Capture/SelectionCapture.swift`
- Repo: https://github.com/ryoochi0112/squai (public)
