# Add a source-level architecture test

**Date:** 2026-10-27 · **State:** committed, not yet run — open until the first two exit
criteria are met

## Background

`CLAUDE.md` rule 3 says the app contains no networking code. Two things stand behind that today.
`scripts/verify-sandbox.sh` proves at the kernel level that a child process cannot reach the
network, but it needs a build and a network connection, so it runs on a developer's machine and
never in CI. The claim about the source itself is only audited: someone reads the code.

`docs/guides/testing.md` says "a rule that can be a test is a test, not a sentence in a guide."
The source half of rule 3 can be a test. So can a layering rule that `Package.swift` describes
but nothing checks: `Sources/Core` is the engine both front ends depend on, and it depends on
nothing that needs a screen.

## Outcome

CI fails if a file under `Sources/` mentions networking, or if a file under `Sources/Core/`
imports anything other than `Foundation`. Each failure names the file and says why the rule
exists.

## Constraints

- One new file, `Tests/TranscribeCoreTests/ArchitectureTests.swift`, plus one row in
  `docs/guides/testing.md` and this folder. No change to `Sources/`, `Package.swift`,
  `README.md` or `CLAUDE.md`.
- Read the source as text from the filesystem, found relative to `#filePath`, so it runs the
  same from Xcode and from `scripts/test.sh`. No new dependencies.
- Strip comments before matching, so a symbol named in prose does not fail the build. Strings
  are kept. The stripper must not treat `//` or `/*` inside a string as a comment: Sources has
  raw-string regexes (`#"..."#`), multi-line strings, and `models/*` inside a `///` comment.
- Rule 4: this checks the **source**. It does not replace `verify-sandbox.sh` and must not be
  described as if it did.

## Steps

1. Write the test: a list of rules (pattern, scope, reason), a directory walk, a comment
   stripper, one assertion per file and rule that names both.
2. Run `./scripts/test.sh`. It must pass on the current tree; if it does not, the test is wrong.
3. Add `import AppKit` to one Core file, run the tests, record which test fails and what it
   says, then remove the line.
4. Add the row to the table in `docs/guides/testing.md`.
5. Tick the boxes below, fill in "What went wrong", set State to done, commit.

## Exit criteria

- [ ] `./scripts/test.sh` is green and the new tests appear in its output. **Not run.** The file
      was only type-checked, with `swiftc -typecheck`, which passed.
- [ ] Seen to fail: with `import AppKit` added to one Core file, the new test fails for that
      reason with the file named; then the line is removed. The failing test is recorded here.
      **Not done.** `Sources/` was never touched.
- [x] `docs/guides/testing.md`: one new row in the "What each test file protects" table.
- [ ] This plan has its State set to done, every box ticked or honestly left unticked, and a
      "What went wrong" section. The section is written and the boxes are honest; State is not
      done, because the tests have not run.
- [x] One commit, in the repository's existing style, containing the test, the doc row and this
      folder. Nothing else in the diff.
- [x] No personal data anywhere: no names, emails, machine names or home-directory paths in
      files or commit metadata. The author is the repository's existing identity, with no email.

## What went wrong

- **The agent could not run the tests, and found out only after the plan was approved.** SwiftPM
  compiles `Package.swift` inside `sandbox-exec`, and the agent's own session sandbox refuses a
  sandbox inside itself. Passing `--disable-sandbox` through `test.sh` was refused by the
  session's permission check. The plan never checked that `test.sh` could run at all; that check
  takes seconds and belongs before the steps that depend on it.
- **Committed before the test was seen green or seen to fail**, at the owner's request, within
  the time box. Neither rule has been seen to catch anything in the real tree. The only evidence
  is that the file type-checks.
- **An ambiguous instruction was read as a go.** The reply to the plan was "commit", which was
  taken to mean "go ahead and finish". The owner then asked to commit the code.
- **One test beyond the brief:** `testTheRulesSeeCodeButNotComments` feeds each rule and the
  comment stripper a sample, so that rule 2 and the stripping have a check that does not touch
  `Sources/`. It has not run either.

**Left open, and this task stays open until it is done:** run `./scripts/test.sh` outside the
agent's sandbox; add `import AppKit` to `Sources/Core/Tuning.swift`, run
`./scripts/test.sh --filter ArchitectureTests`, record which test fails and what it says, then
remove the line. Tick the first two boxes and set State to done.
