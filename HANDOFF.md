# HANDOFF — squai (2026-10-14, session 2)

## Verified state

`main` = `5e370b8` (PR ryoochi0112/squai#2 merged). This branch `fix/error-diagnostics` is rebased
onto it (`ad00544` capture rewrite + this note). Tree clean except the untracked root
`RESEARCH-desktop-pet-translator.md` (byte-identical duplicate of the docs/research file).

DONE (verified this session):
- **v2 spec written and critic-reviewed**: `docs/specs/2026-10-14-squai-v2-squad-spec.md`.
  15 acceptance criteria, all pass the fresh-context critic (3 passes). §4b records Git process.
  Decisions are in its §5 table (users = non-devs; 1 folder = 1 member with `skill.json`;
  Claude/ChatGPT via `claude -p` / `codex exec`, API key fallback; click-to-run + optional
  hotkey; Copy/Replace; Codex look import; OpenAI Images generation; empty first run; Apple
  Translation dropped).
- **GitHub setup**: `.github/workflows/verify.yml` (`make verify` on `macos-26`, job `verify`)
  ran green on PR #2 and on `main`. Branch protection on `main`: PR required (0 approvals),
  `verify` check required + strict, admins enforced, no force push / delete.
- **Makefile fix**: `make build` now `set -o pipefail` so a failed xcodebuild exits non-zero
  (macOS make 3.81 ignores `.SHELLFLAGS`; verified bogus scheme → exit 2).
- **rstaff profile** created: `/Users/ryoochi/rstaff/profiles/squai.md`.
- `make verify` green on this tree: 20 SquaiCore tests, Debug build.

未検証 (unverified):
- `ad00544` capture rewrite (modifier-release wait, `.cgSessionEventTap`, Edit ▸ Copy menu
  fallback, per-stage diagnostics). Compiles; never exercised against Safari.
- v1 AC1–AC8, AC10 remain manual and unticked.

## Open decisions

1. ~~v2 initiative grill~~ → done; spec merged. Next step is `/rstaff-engineer:design`.
2. Yes/no: open a PR for `fix/error-diagnostics` even if capture is still failing? It is
   strictly better diagnostics than `main`. Recommended: yes, after one manual retry. Note
   `main` now requires a PR + green `verify`, so direct push is impossible anyway.
3. Yes/no: delete the untracked root `RESEARCH-desktop-pet-translator.md` duplicate.
4. v2 spec §5 open questions need a human call before design: image-generation alternatives
   to an OpenAI API key; CLI invocation model (cwd, timeout, 10 s budget); ChatGPT API
   fallback model; default hotkey suggestion; Replace mechanism (AX write vs ⌘V).

## Environment

```bash
cd /Users/ryoochi/squai
make verify          # swift test (Packages/SquaiCore) + xcodebuild Debug, exit 0 expected
make run             # or open Squai.xcodeproj and run scheme Squai
```

- Toolchain: Xcode 26.6, Swift 6.3, macOS 26.5.1, xcodegen 2.46. `make gen` after editing `project.yml`.
- No signing identity, no Apple ID: re-add squai in System Settings → Privacy & Security →
  Accessibility after every rebuild.
- Claude key, if used, lives in Keychain service `com.squai.anthropic`.
- rstaff completion gate blocks session stop until a plain `make verify` exits 0 on the tree.

## Next actions

1. Fresh session: `/rstaff-engineer:design docs/specs/2026-10-14-squai-v2-squad-spec.md` →
   PLAN + task ledger. Resolve open decision 4 items during design.
2. In parallel or before: decide open decision 2. If yes: ⌘R → re-add Accessibility → select
   text in Safari → ⌥⌘T → paste the bubble's `Diagnostics:` line; then `git push -u origin
   fix/error-diagnostics` and open a PR (CI `verify` must pass).
3. Decide open decision 3 (delete duplicate research file).
4. v2 build will remove `AppleTranslationBackend`, `TranslateSkill`, and the ja/en-specific
   hotkeys in `App/Squai/Hotkeys.swift`; v1 spec stays as history.

## Pointers

- v2 spec: `docs/specs/2026-10-14-squai-v2-squad-spec.md`
- v1 spec: `docs/specs/2026-10-14-squai-v1-spec.md`
- rstaff profile: `/Users/ryoochi/rstaff/profiles/squai.md`
- CI: `.github/workflows/verify.yml`; PR #2: https://github.com/ryoochi0112/squai/pull/2
- Capture: `App/Squai/Capture/SelectionCapture.swift`; error text: `AppDelegate.describe(_:)`
- Skills protocol (to be extended in v2): `Packages/SquaiCore/Sources/SquaiCore/Skills.swift`
- Repo: https://github.com/ryoochi0112/squai (public)
