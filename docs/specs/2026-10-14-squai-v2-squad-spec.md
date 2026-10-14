# squai v2 — build your own AI squad (spec)

Date: 2026-10-14. Status: draft for `/rstaff-engineer:design`. Supersedes the single-pet,
translate-only model of `docs/specs/2026-10-14-squai-v1-spec.md`. Grill transcript: session
2026-10-14 (decisions recorded in §5).

## 1. Problem & user value

A non-developer wants a few small creatures on the desktop, each with one job they defined in
plain language ("translate to natural English", "make this polite Japanese", "summarize in 3
bullets"), and wants to use them on any selected text in any app with one click. Today squai
has one hard-coded translator and adding anything else requires Swift. v2 lets a user create,
edit, share, and delete squad members without code, using the Claude or ChatGPT subscription
they already pay for. "On-device" means **the squad is always on the display**; inference is
cloud (Claude / ChatGPT), not local.

## 2. Users & context

- **Who:** macOS 26 users with a Claude (Pro/Max via Claude Code CLI) or ChatGPT (via Codex
  CLI) subscription. No Swift, no terminal needed after CLI install.
- **Trigger:** select text in any app → click a pet (or press that pet's optional hotkey).
  Several times an hour while reading or writing.
- **Authoring:** Settings → Squad (GUI editor) or by dropping a member folder into
  `~/Library/Application Support/squai/pets/`. Looks can also come from `~/.codex/pets/`.
- **Sharing:** zip one member folder and send it; recipient drops it in and it appears.

## 3. Acceptance criteria

Each criterion is checked manually in the running Debug app unless it names `swift test`.
"Member folder" = one directory containing `pet.json`, the sprite sheet, and `skill.json`.

1. **Empty first run.** On first launch with no member folders, the app shows no pet and opens
   Settings → Squad on the "Create member" form. Falsifier: a pet appears, or Settings does not
   open, or the form is not the create form.
2. **Create via GUI.** A user can create a member by filling name, prompt, backend (Claude or
   ChatGPT), look (picked from the bundled library or an imported folder), optional hotkey,
   and visible on/off, then pressing Save. Within 1 s the pet appears on the desktop and a new
   member folder exists under `~/Library/Application Support/squai/pets/<id>/` containing
   `pet.json`, the sprite sheet, and `skill.json` with exactly those values. Falsifier: any
   file missing, any value differs from the form, or the pet is not visible.
3. **File is source of truth.** Create a member whose prompt is "Reply with exactly the word
   PING" and run it on any selection (bubble body `PING`). Edit `skill.json` on disk so the
   prompt is "Reply with exactly the word PONG", choose Squad → Reload (or relaunch): the GUI
   prompt field now reads PONG and the next run's bubble body is `PONG`. Deleting the folder
   and reloading removes the pet and its GUI row. Falsifier: GUI shows PING, the bubble shows
   PING, or the deleted member persists.
4. **Click runs the skill.** With text selected in Safari, VS Code, and Slack, left-clicking a
   visible pet captures the selection and, within 10 s, shows a bubble next to that pet
   containing the backend's response to `prompt + "\n\n" + selection`. The source app keeps
   focus and its selection. Falsifier: no bubble, bubble on the wrong pet, source app loses
   focus or selection, or the response ignores the prompt (test with prompt
   "Reply with exactly the word PING" → bubble body is `PING`).
5. **Per-member hotkey.** A member with a hotkey set in `skill.json`/GUI runs on that hotkey
   exactly as in AC4, including when `visible` is false. Two members cannot be saved with the
   same hotkey (GUI shows an inline error). Falsifier: hotkey does nothing for a hidden member,
   or a duplicate hotkey saves.
6. **Right-click re-shows last result.** Use a member with prompt "Echo the input exactly".
   Before any run, right-click shows a bubble reading "No result yet". Select `alpha`, left-click
   the pet → bubble `alpha`. Select `beta`, right-click → bubble still `alpha` (no run). With
   `beta` still selected, left-click → bubble `beta`. Falsifier: right-click after selecting
   `beta` shows `beta`, or left-click with `beta` selected shows `alpha`.
7. **Backend via CLI.** Confirm Keychain holds no `com.squai.anthropic` / `com.squai.openai`
   item. Put a shim `claude` first on `PATH` that appends its arguments and stdin to
   `/tmp/squai-cli.log` and prints `SHIM-OK`; run a Claude member → bubble body `SHIM-OK` and the
   log contains `-p` plus the assembled prompt. Repeat with a shim `codex` for a ChatGPT member
   (log contains `exec`). Settings shows per backend one of: "CLI found (<path>)", "CLI not
   found", "API key set"; renaming the shim away flips it to "CLI not found". Falsifier: the run
   asks for an API key, the log is empty, the body is not `SHIM-OK`, or the status line does not
   flip.
8. **API key fallback.** With the CLI absent and an API key stored in Keychain (service
   `com.squai.anthropic` / `com.squai.openai`), the run succeeds through the Messages API
   (Claude) or Responses API (ChatGPT). With neither CLI nor key, the bubble reads
   "<Backend> is not set up" with a button that opens Settings. Keys are never written outside
   Keychain (`grep -r` of Application Support and Preferences finds none). Falsifier: any of
   these three states behaves differently.
9. **Copy and Replace.** The result bubble has Copy and Replace. Copy puts the body on the
   clipboard. Replace pastes the body over the original selection in the source app and then
   restores the previous clipboard contents; if the paste cannot be delivered (selection gone,
   focus lost), the bubble changes to "Copied — could not replace" and the clipboard holds the
   body. Test in TextEdit (success) and after clicking into another app before pressing
   Replace (failure path). Falsifier: clipboard not restored after a successful replace, or
   silent failure.
10. **All members visible, independent positions.** Three visible members show at once, each
    draggable; after quit and relaunch each is at its saved position. Toggling `visible` off in
    Settings removes that pet immediately and keeps the others. Falsifier: positions collapse,
    a hidden pet still shows, or a toggle affects another member.
11. **Codex look import.** A look-only folder (pet.json + sheet, no skill.json) in
    `~/.codex/pets/` appears in the look picker but not as a squad member. Choosing it in the
    create form copies the folder into squai's directory and writes `skill.json` there;
    `~/.codex/pets/` is never written. Falsifier: look-only folder shows as a pet on the
    desktop, or `~/.codex/pets/` gains a file.
12. **Share by folder.** Zipping a member folder, deleting it, and unzipping it back (or into
    another user's squai directory) restores the member with identical name, prompt, backend,
    hotkey, and look, with no GUI step. Falsifier: any field lost, or the member needs manual
    re-creation.
13. **Generate a look.** In the create form, "Generate look" takes a text description and,
    with an OpenAI API key set, saves `spritesheet.png` into the member folder. Checks: `sips -g
    pixelWidth -g pixelHeight` reports 1536×1872; the form's "Preview rows" control lists the 9
    row names (idle, running-left, running-right, waving, jumping, failed, waiting, running,
    review) and selecting each plays that row's 8 cells in the preview, with no cell fully
    transparent (the `swift test` slicer case in AC14 counts 72 non-empty cells for the saved
    file). Without a key, pressing the button shows inline text "Needs an OpenAI API key
    (Settings)" and "Make one in Codex with /hatch — it appears here automatically", and no
    dialog. Falsifier: wrong dimensions, a row name missing from Preview rows, a row whose
    preview does not change frames, an empty cell, or a dialog on the no-key path.
14. **Unit tests.** `swift test` passes for: `skill.json` decode/encode round-trip (all five
    fields plus unknown-field tolerance), member-folder scan (look-only vs full member),
    prompt assembly (`prompt + "\n\n" + selection`), hotkey-collision detection, the CLI
    argument builder for `claude -p` and `codex exec`, and a sprite-sheet slicer check that a
    given PNG yields 72 cells of 192×208 with none fully transparent. Falsifier: any listed
    test absent or failing.
15. **Translate member parity.** A member with prompt "Translate between Japanese and English;
    detect the direction; output only the translation" run on `こんにちは` yields an English
    bubble and on `hello` yields a Japanese bubble. Falsifier: wrong direction or extra
    commentary in the body.

**Golden sample.** Member "Polite" (backend `claude`, prompt: "Rewrite in polite business
Japanese. Output only the rewritten text."). Selection: `明日の会議、来れる？`. Bubble next to
the Polite pet:

```
明日の会議にご出席いただけますでしょうか。
                                   [Copy] [Replace]
```

`skill.json` written for that member:

```json
{ "name": "Polite", "prompt": "Rewrite in polite business Japanese. Output only the rewritten text.",
  "backend": "claude", "hotkey": "opt+cmd+p", "visible": true }
```

## 4. Scope & out-of-scope

**In:** member folders; Squad GUI (create/edit/delete/reload/visible toggle); click + hotkey
invocation; Claude and ChatGPT via CLI with API-key fallback; Copy/Replace; multi-pet overlay;
Codex look import; OpenAI Images generation; onboarding to the create form; removal of the
Apple Translation backend and the v1 `TranslateSkill`.

**Out:** local inference (Apple Foundation Models, Apple Translation); a member picker popup;
driving Claude.app / ChatGPT.app by automation; per-member default output mode (auto-copy /
auto-replace) and Undo; engine-type skills other than prompt; chat with a pet; multiple skills
per pet; a pet marketplace or cloud sync; Windows/Linux; App Store sandbox; streaming
responses; image or file input (text selection only).

## 4b. Git / repository process

- **Repo:** `ryoochi0112/squai`, public, personal account. Default branch `main`.
- **CI:** `.github/workflows/verify.yml` runs `make verify` (job name `verify`) on a
  `macos-26` runner for every PR and every push to `main`. `make verify` must fail when
  `xcodebuild` fails (the Makefile sets `pipefail`).
- **Branch protection on `main`:** PR required, `verify` check required and up to date,
  no direct pushes, no force pushes, no deletions. Admin is not exempt. Merge is a human
  action.
- **Branching:** one branch per change (`feat/…`, `fix/…`); squash merge allowed.
- **Secrets:** API keys live only in Keychain (`com.squai.anthropic`, `com.squai.openai`).
  Nothing in the repo, CI, or test fixtures may contain a real key; AC8 greps for this.
- **Manual ACs:** CI proves only `SquaiCore` tests and the Debug build. Overlay, capture,
  bubble, and CLI behavior are ticked in this spec by a human after seeing them.

## 5. Open questions & decisions

Decisions from the grill (2026-10-14):

| # | Question | Decision |
|---|---|---|
| 1 | Who builds? | Non-developer end users; no Swift. |
| 2 | What is a skill? | Prompt + engine types allowed, but Apple Translation dropped; translation is a prompt. |
| 3 | Authoring surface | Files are source of truth; GUI is an editor over them. |
| 4 | "On-device" | Pet is always on the display. Inference is cloud. |
| 5 | Backend | Per member: Claude or ChatGPT. Primary = user's subscription via `claude -p` / `codex exec`; API key only as fallback. |
| 6 | Invocation | Click the pet + optional per-member hotkey. No popup. Right-click = last result. |
| 7 | Display | All members at once; per-member visible toggle; hidden = hotkey only. |
| 8 | Looks | Bundled library + Codex folder import + `/hatch` guidance + own generation (OpenAI Images). |
| 9 | Output | Bubble + Copy + Replace (explicit button). |
| 10 | First run | Empty squad; onboarding opens the create form. |
| 11 | File structure | 1 folder = 1 member (`pet.json` + sheet + `skill.json`). Zip = share unit. |

Still open (human call before `/rstaff-engineer:design`):

- **Image generation alternatives.** The user welcomes a better option than an OpenAI API key.
  Research: does Codex CLI expose image generation under a ChatGPT subscription? Does Claude
  Code offer any image tool? Could a text-LLM pixel-grid fallback be acceptable quality? Report
  findings; the OpenAI Images path stays the v2 default until then.
- **CLI invocation model.** `claude -p` and `codex exec` may start slow (multi-second) and
  may read the current directory; design must pick a working directory and a timeout and
  confirm neither CLI writes to the user's project. AC4's 10 s budget is a placeholder to tune.
- **ChatGPT API fallback.** Confirm the Responses API model to use and whether a key-only user
  is realistic given the "subscription first" stance; could be deferred to v2.1 if CLI coverage
  is sufficient.
- **Default hotkey for the first member.** None assigned by default; confirm the onboarding
  should suggest one.
- **Replace mechanism.** AX `kAXSelectedTextAttribute` write vs synthetic ⌘V; design decides,
  AC9 only fixes the observable behavior.
