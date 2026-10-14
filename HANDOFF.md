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

1. ~~v2 initiative grill~~ → done; spec merged.
2. ~~PR for `fix/error-diagnostics`~~ → **yes**: open it without waiting for the manual Safari
   retry. It is strictly better diagnostics, CI gates it, and v2 AC4 testing re-exercises capture.
3. ~~Delete root `RESEARCH-desktop-pet-translator.md`~~ → **done** (byte-identical to
   `docs/research/2026-10-14-desktop-pet-translator.md`, verified with `cmp`).
4. ~~v2 spec §5 open questions~~ → resolved in `/rstaff-engineer:design` (spec §5 rows 12–17;
   design doc `docs/specs/2026-10-14-squai-v2-design.md`).

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

1. Open the PR for `fix/error-diagnostics` (capture rewrite + design docs).
2. After merge: `/rstaff-engineer:build` (or `/rstaff-engineer:dispatch`) on the ledger
   `/Users/ryoochi/rstaff/var/specs/squai/squai-v2-squad.tasks.md`, branch `feat/v2-squad`.
3. First manual pass: confirm capture in Safari (AC4) before judging UI tasks.

## Pointers

- v2 spec: `docs/specs/2026-10-14-squai-v2-squad-spec.md`
- v2 design: `docs/specs/2026-10-14-squai-v2-design.md`; ledger: `/Users/ryoochi/rstaff/var/specs/squai/squai-v2-squad.tasks.md`
- v1 spec: `docs/specs/2026-10-14-squai-v1-spec.md`
- rstaff profile: `/Users/ryoochi/rstaff/profiles/squai.md`
- CI: `.github/workflows/verify.yml`; PR #2: https://github.com/ryoochi0112/squai/pull/2
- Capture: `App/Squai/Capture/SelectionCapture.swift`; error text: `AppDelegate.describe(_:)`
- Skills protocol (to be extended in v2): `Packages/SquaiCore/Sources/SquaiCore/Skills.swift`
- Repo: https://github.com/ryoochi0112/squai (public)
