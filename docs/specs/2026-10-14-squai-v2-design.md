# squai v2 — engineering design

Date: 2026-10-14. Contract: `docs/specs/2026-10-14-squai-v2-squad-spec.md` (the spec's ACs are the
acceptance gate; this doc decides *how*). Task ledger: `$RSTAFF_HOME/var/specs/squai/squai-v2-squad.tasks.md`.

## 1. Problem & user value

A non-developer selects text anywhere, clicks one of their own creatures, and gets that creature's
job done on the text (translate, rewrite, summarize) through the Claude or ChatGPT subscription they
already pay for. They create, edit, share, and delete creatures without code. v1's hard-coded
translator, Apple Translation backend, and ja/en hotkeys go away.

## 2. Evidence behind the §5 decisions (measured on this Mac, 2026-10-14)

| Probe | Result |
|---|---|
| `claude -p` 2.1.292, `--model haiku`, tools/settings/MCP off, empty cwd | 3.5 s wall (2 runs). Body `PING`. Nothing written to cwd; no session saved. |
| `claude --bare` | Not usable: auth is `ANTHROPIC_API_KEY` only, OAuth/subscription never read. |
| `codex exec` 0.159.0, default model `gpt-6.1-sol`, `--ephemeral --sandbox read-only` | 8.4–10.4 s at default (medium) and 9.6 s at `low`. `minimal` is rejected by this model (HTTP 400). |
| `codex exec` image generation, ChatGPT login, no `OPENAI_API_KEY` | Built-in `image_gen` returned 1536×1024 RGBA PNG in ~70 s. `codex features list`: `image_generation stable true`. |
| `~/.codex/skills/hatch-pet` | Present. Builds a full 8×9 atlas (≈10 image jobs → 10–20 min) and packages `pet.json` + `spritesheet.webp`. Its scripts need Python Pillow (missing on this Mac). Codex pet contract allows PNG or WebP and **fully transparent unused cells**. |
| `/opt/homebrew/bin/codex` | `#!/usr/bin/env node` script → the child needs `node` on `PATH`. `claude` is a native Mach-O. |

## 3. Approach

### 3.1 Modules

Testable logic lives in `Packages/SquaiCore` (covered by `swift test`); AppKit glue stays in `App/Squai`.

| Layer | Type | Responsibility |
|---|---|---|
| Core | `SkillFile` | `skill.json` Codable: `name`, `prompt`, `backend` (`claude`\|`chatgpt`), `hotkey` (String?), `visible` (Bool). Unknown keys ignored on decode; encode uses sorted keys + pretty print. |
| Core | `HotkeySpec` | Parse/format `"opt+cmd+p"` (tokens `ctrl`, `opt`, `shift`, `cmd` + one key `a–z`, `0–9`, `f1–f12`, `space`). Normalized order `ctrl+opt+shift+cmd+key`. Collision = normalized equality. |
| Core | `SquadLibrary` | Scans member root and look roots. Folder with `pet.json` + `skill.json` = member; `pet.json` only = look. Member id = folder name. `~/.codex/pets` is read-only and contributes looks only. |
| Core | `PromptAssembler` | `prompt + "\n\n" + selection`. |
| Core | `CLIInvocation` + builders | Pure value: executable, args, stdin, cwd, env, timeout. Builders for `claude` and `codex` (§3.2). |
| Core | `CLIRunner` | Runs an invocation with `Process`; writes stdin, collects stdout/stderr, SIGTERM then SIGKILL at timeout; returns exit code + output. |
| Core | `CLILocator` | Resolves `claude` / `codex` (§3.2) and builds the child `PATH`. |
| Core | `ClaudeAPI` (refactor) | Messages API with a generic system prompt + user content; drops the translation JSON payload. |
| Core | `BackendRouter` | Claude: CLI → Keychain key → `.notSetUp`. ChatGPT: CLI → `.notSetUp`. Returns a `SkillOutput` or a typed error. |
| Core | `SpriteSheetValidator` | Size must be 1536×1872; each of 9 rows must have ≥1 cell with any alpha > 0. |
| Core | `HatchInvocation` | Builds the `codex exec` look-generation invocation + preflight result (§3.5). |
| App | `SquadController` | Owns one `PetController` + `BubbleController` per visible member; reload; runs; last result per member. |
| App | `ReplaceService` | Copy and Replace (§3.4). |
| App | Settings | Tabs: **Squad** (list, editor, look picker, Generate look), **Backends** (status lines, Claude key), **General**. |

v1 removals: `AppleTranslationBackend`, `TranslateSkill`, `LanguageDetector`, `TranslationResult`'s
translation-specific errors (kept only what `ClaudeAPI` still needs), `Hotkeys.swift` v1 names,
`Preferences.selectedPetID` / `petOrigin`, "Ask Claude" and "Download language pack" bubble buttons.
`PetSkill`/`SkillRegistry` are replaced by members; nothing else depends on them.

### 3.2 CLI invocation model (spec §5 row 13)

- **cwd:** a fresh `FileManager.default.temporaryDirectory/squai-run-<uuid>/`, created per run,
  deleted after. Never the user's home or a project. Why over a shared fixed dir: no cross-run
  state, and a stray write is cleaned up automatically.
- **Claude:** `claude -p --model haiku --output-format text --tools "" --setting-sources ""
  --strict-mcp-config --no-session-persistence --disable-slash-commands --system-prompt <S>`,
  assembled prompt on **stdin**. `S` = "You transform text for the user. Follow the instruction
  exactly. Output only the result, with no preamble." Output = trimmed stdout.
  Why stdin: no `ARG_MAX` limit and the selection does not appear in `ps`.
  Why `haiku`: 3.5 s measured; the user's default model (Opus/Fable) is slower for one-shot edits.
- **ChatGPT:** `codex exec --skip-git-repo-check --ephemeral --sandbox read-only --ignore-rules
  --color never -c model_reasoning_effort="low" -C <cwd> -o <cwd>/last-message.txt -`, prompt on
  stdin. Output = `last-message.txt` if present, else trimmed stdout (keeps the AC7 shim working).
  `--ignore-user-config` is **not** used: it would drop the user's model choice; auth is unaffected
  either way. Read-only sandbox means generated shell commands cannot write anywhere.
- **Timeouts:** 30 s Claude, 60 s ChatGPT, then SIGTERM, 2 s grace, SIGKILL; bubble "Claude took
  too long (30 s). Try again." The pet plays `running` while waiting.
- **Locating the CLI:** GUI apps get launchd's `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), not the
  shell's. Resolution order, first executable hit wins: (1) `$SHELL -lic 'command -v <name>'`
  run once at launch and on Settings → Backends → Recheck, 3 s timeout; (2) fixed dirs
  `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.claude/local`, `~/.npm-global/bin`,
  `~/.bun/bin`. Child `PATH` = CLI's dir + login-shell `PATH` + fixed dirs + system dirs (so
  `node` resolves for `codex`). Why the login shell first: AC7's shim-first-on-`PATH` check and
  nvm/volta installs only work through it.
- **Exit handling:** non-zero exit → bubble shows the first 300 chars of stderr. A Claude exit
  with "not logged in"/auth text, or Codex "Not logged in" → "<Backend> is not logged in. Run
  `claude` (or `codex login`) once in Terminal."

### 3.3 Run flow

```
click / hotkey(member)
  → SelectionCapture.selectedText()  → (text, CaptureContext{pid, bundleID, axFocused?})
  → PromptAssembler(prompt, text)
  → BackendRouter(member.backend)
       claude:  CLIRunner(claude invocation) | ClaudeAPI(key) | .notSetUp
       chatgpt: CLIRunner(codex invocation)  | .notSetUp
  → SkillOutput(body) → member.lastResult = (body, context)
  → that member's BubbleController.show(.result) with [Copy] [Replace]
```

- One run per member at a time: a click while running is ignored (pet already shows `running`).
  Different members may run concurrently.
- Right-click: show `lastResult` or "No result yet"; never runs (AC6).
- Hotkeys: one `KeyboardShortcuts.Name("member.<id>")` per member with a hotkey, set from
  `skill.json` on every reload (file is source of truth; UserDefaults is a cache).
- Pet positions: `UserDefaults` key `petOrigin.<id>`; new members cascade 110 pt left of the
  previous one from the bottom-right default.

### 3.4 Copy and Replace (spec §5 row 17)

- **Copy:** clear pasteboard, write body as `.string`.
- **Replace:** (1) if `NSWorkspace.frontmostApplication.pid != context.pid` → failure path;
  (2) snapshot pasteboard items (same code as capture); (3) write body; (4) wait for modifier
  release; post ⌘V (key 9) via `.cgSessionEventTap`; (5) after 400 ms restore the snapshot.
  **Failure path:** leave the body on the pasteboard; bubble becomes "Copied — could not replace".
- **Replace safety refinements (added in T7):** (a) the snapshot is restored only if the
  pasteboard `changeCount` is unchanged since the body was written, so a copy the user makes in the
  400 ms window wins over the older snapshot; (b) squai's own pid is never a Replace target (failure
  path); (c) capture and Replace never overlap — a run is ignored while a Replace is in flight and
  Replace is ignored during a capture — so one operation's restore cannot overwrite the other's.
  The pid guard is re-checked after the modifier-release wait.
- **Why ⌘V over AX `kAXSelectedTextAttribute` write:** the AX write works in Cocoa text views but
  is ignored or reports success without effect in Chromium/Electron (VS Code, Slack) and many web
  fields — a silent failure AC9 forbids. ⌘V follows the app's own paste path (undo works) and the
  pid guard gives a reliable failure signal for the AC9 "focus lost" case. Known gap: a paste the
  app silently rejects (read-only field) cannot be detected; documented, not handled.
- AC9 failure test path: clicking another app hides the bubble (global click monitor), so the
  tester right-clicks the pet to re-show the last result and presses Replace there.

### 3.5 Look generation (spec §5 row 12)

- **Preflight** (shown inline in the form, no dialog): `codex` located; `codex login status`
  says ChatGPT; `~/.codex/skills/hatch-pet/SKILL.md` exists; `python3 -c "import PIL"` succeeds in
  the child env. Each failure has its own line plus "Make one in Codex with /hatch — it appears
  here automatically". Pillow missing → "Look generation needs Python Pillow: run
  `python3 -m pip install --user pillow` in Terminal."
- **Run:** `codex exec --skip-git-repo-check --sandbox workspace-write --color never
  -C ~/Library/Application Support/squai/hatch/<run-id>/ -`, stdin: "Use $hatch-pet to create a
  pet. Description: <text>. Package the final `pet.json` and spritesheet into ./out/ (the
  staging dir) instead of ~/.codex/pets. Do not write anywhere else." No
  `--ephemeral`, so a failed run can be inspected. No timeout beyond 40 min; Cancel terminates.
- **Why `~/.codex/pets` stays untouched:** workspace-write only allows cwd, `/tmp`, and `$TMPDIR`, so the skill's default packaging step into `~/.codex/pets` is blocked by the sandbox.
- **Completion:** validate `out/` with `SpriteSheetValidator`; on pass move it to
  `looks/<id>/` and rescan; on fail show "Generation finished but the sheet is invalid: <reason>"
  and keep `hatch/<run-id>/` for diagnosis. Delete `hatch/<run-id>/` on success.
- **Why not the OpenAI Images API:** needs a key (against "subscription first") and would require
  re-implementing hatch-pet's 9-row consistency pipeline in Swift.

### 3.6 Files on disk

```
~/Library/Application Support/squai/
  pets/<member-id>/   pet.json, spritesheet.(png|webp), skill.json   ← members (zip = share unit)
  looks/<look-id>/    pet.json, spritesheet.*                         ← generated looks (look-only)
  hatch/<run-id>/     codex workdir for a generation run
~/.codex/pets/<id>/   read-only look source
App bundle Pets/      bundled looks (squai-default)
```

- Choosing a look **copies** its folder into a new `pets/<member-id>/`, rewrites `pet.json.id` to
  the member id, and writes `skill.json`. The source is never modified.
- Member id = slug of name (`a–z0–9-`), suffixed `-2`, `-3` on collision. Rename keeps the folder.
- GUI delete moves the folder to the Trash (`FileManager.trashItem`), so it is reversible.
- Writes are atomic (`Data.write(options: .atomic)`).

### 3.7 Onboarding and hotkey default (spec §5 row 16)

No members → no pet; Settings opens on Squad → Create member. The hotkey field is empty with
placeholder "e.g. ⌥⌘1". Saving with `visible = false` and no hotkey is blocked with "Hidden members
need a hotkey". Why no pre-filled default: a pre-filled combo can silently collide with another
app's shortcut, and the user has not chosen it.

## 4. Edge cases & failure modes

| Case | Handling |
|---|---|
| Malformed `skill.json` | Member skipped; Squad list shows a red row "<folder>: skill.json invalid (<error>)"; other members load. |
| `pet.json` ok, sheet missing/wrong size | Member listed with a warning; pet drawn with the bundled default look. |
| Duplicate hotkey across files (edited on disk) | First member by folder order keeps it; others' hotkeys are disabled with a warning row. GUI blocks it on save (AC5). |
| Hidden member without hotkey (edited on disk) | Loaded; warning row "unreachable — add a hotkey". |
| Capture finds no selection | Existing diagnostics bubble on that pet. |
| Accessibility not granted | Existing re-add instructions bubble. |
| CLI not found / key absent | "<Backend> is not set up" + Open Settings (AC8). |
| CLI not logged in | "<Backend> is not logged in…" with the Terminal command. |
| CLI timeout | SIGTERM → SIGKILL; timeout bubble; temp cwd deleted. |
| CLI prints nothing | "The response came back empty." |
| Two clicks on one member | Second ignored while running. |
| Replace after focus change | Pid guard → "Copied — could not replace". |
| Replace into read-only field | Paste silently ignored; not detectable (documented gap). |
| Pasteboard had files/images | Snapshot keeps every type of every item; restored after Replace and after capture. |
| Look generation fails mid-way | Error inline; `hatch/<run-id>/` kept; no partial look in picker. |
| App quits during generation | Child is terminated in `applicationWillTerminate`; staging dir left; next launch deletes stale `hatch/*` older than 24 h. |
| Unzipped member collides with existing folder name | Finder already renames ("x 2"); id = folder name, so both load. |
| Codex look id equals a member id | Looks and members are separate lists; copy-on-choose gives the member its own id. |

## 5. Test matrix

| Area | Unit (`swift test`) | Integration (`swift test`, real process/files) | Manual e2e (Debug app) |
|---|---|---|---|
| `skill.json` codec | round-trip 5 fields; unknown key ignored; bad backend rejected | — | AC2, AC3, AC12 |
| Hotkey | parse/format/normalize; collision; invalid token | — | AC5 |
| Squad scan | — | temp dirs: member vs look-only; malformed skill.json skipped; codex root never written | AC3, AC11 |
| Prompt assembly | exact `prompt\n\nselection` | — | AC4, AC15 |
| CLI builders | exact argv for claude and codex; stdin carries prompt | — | AC7 |
| CLI runner | — | shim script: stdin echoed, args logged, exit code, timeout kills a `sleep 60` shim in <3 s | AC4, AC7 |
| CLI locator | dir precedence with injected dirs; child PATH composition | — | AC7 status flip |
| Backend router | stubbed CLI/transport/key: CLI wins, key fallback, notSetUp for both backends | — | AC8 |
| Claude API | request JSON shape; text extraction; HTTP error | — | AC8 |
| Sprite validator | — | generated PNGs: valid sheet, wrong size, one empty row | AC13 |
| Hatch invocation | argv, prompt text, preflight result mapping | — | AC13 |
| Overlay / positions / visible | — | — | AC1, AC10 |
| Copy / Replace | — | — | AC9 |
| Translate parity | — | — | AC15 |

## 6. Definition of Done

- `make verify` green (= `swift test --package-path Packages/SquaiCore` + `xcodebuild` Debug,
  `CODE_SIGNING_ALLOWED=NO`). The gate covers both touched packages (SquaiCore and the app target;
  `make build` runs `make gen`, so new app files are picked up). CI job `verify` green on the PR.
- Spec AC14 tests present and passing.
- Manual ACs 1–13 and 15 checked in the running Debug app and ticked in the spec by the human.
  A user can: start with an empty squad and create a member in the form; click it on selected text
  in Safari and see the result next to it; Copy or Replace the result; give a hidden member a
  hotkey; edit `skill.json` on disk and Reload; zip a member and restore it; import a Codex look;
  generate a new look through Codex without an API key.

## 7. Risks, out of scope, human decisions

- **Accessibility re-grant per rebuild** slows every manual AC pass (ad-hoc signing). Unchanged.
- **Capture rewrite `ad00544` is still unverified in Safari**; AC4 depends on it. First manual
  pass should confirm it before UI work is judged.
- **hatch-pet is a Codex-side skill we do not control**; its packaging path or prompt contract may
  change. Validation of the output (not trust in the skill) is the guard. Generation is slow
  (10–20 min) and uses ChatGPT quota.
- **Pillow** is a prerequisite for hatch-pet; non-developers may stall there. Inline instruction only.
- **`--model haiku`** is a fixed app-level choice; per-member model is out of scope (v2.1 candidate).
- **Replace into a read-only field** fails silently (documented gap).
- Out of scope (unchanged from spec §4): streaming, chat, multiple skills per pet, marketplace,
  ChatGPT API key, OpenAI Images API.
