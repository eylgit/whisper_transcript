# Adopt the guides / tasks docs structure

**Date:** 2026-10-05 · **State:** done

## Background

Everything known about this project lived in the README and in code comments. The README is
written for a person deciding whether to trust the tool. Nothing told a coding agent which rules
must never be broken, which command proves a change is safe, or how work is recorded. The first
build had no written plan at all.

## Outcome

- An agent starting cold reads one short file and knows the commands, the rules, and where to look.
- Lasting knowledge (`docs/guides/`) is separate from records of work (`docs/tasks/`).
- The first build has a record, clearly marked as written afterwards.

## Constraints

- No change to application code, tests or scripts.
- No change to any claim in the README. Guides point into the README and the code; they do not replace it.
- The reconstructed plan must say plainly that it is a reconstruction.
- Nothing personal: the owner is "the owner", and no session text is quoted.

## Steps

1. Add `CLAUDE.md` at the root: commands, non-negotiable rules, an index of the guides, how tasks work.
2. Add four guides: `overall.md`, `how-transcription-works.md`, `offline-guarantee.md`, `testing.md`.
3. Reconstruct `docs/tasks/2026-09-04_initial-build/plan.md` from the working session and the commit history.
4. Add `docs/` and `CLAUDE.md` to the layout listing in the README.
5. Ignore `.swiftpm/`, which Xcode creates and which holds per-user files.

## Exit criteria

- [x] `CLAUDE.md` exists, is under 70 lines, and every file it links to exists.
- [x] Every file path named in a guide exists.
- [x] `./scripts/test.sh` passes with the same 41 tests as before.
- [x] `./scripts/verify-sandbox.sh` passes, all four checks.
- [x] No file under `Sources/`, `Tests/` or `scripts/` is changed.

## What went wrong, and what is left

- **Writing the testing guide exposed a wrong claim.** Checking which test catches the
  opening-pause fault showed the README credits the wrong one. The guide is accurate; the README
  is not yet corrected. That is the next task.
- **The guides restate some things the README also says**, such as the sandbox profile. Two
  copies can drift.

**Not done, on purpose:**

1. A scored set of recordings, so tuning changes are judged by a number, not by eye.
2. An automatic check that guides have not gone stale, starting with "every path a guide names exists".
3. A fixed seed and shrinking for the randomised test.
4. A home for decision records.
