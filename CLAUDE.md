# Transcribe — instructions for coding agents

Transcribe turns an audio file into a Markdown transcript on macOS, offline, using whisper.cpp.
It exists to contain two faults of the speech model: inventing text during silence, and getting
stuck repeating a sentence.

This file is the entry point. It is short on purpose: read it, then open only the guides the
task in hand needs.

## Commands

```sh
./scripts/test.sh             # unit tests, under a second once built; needs Xcode for XCTest
./scripts/build-app.sh        # build the CLI and the app into build/
./scripts/verify-sandbox.sh   # prove the sandbox blocks what it claims; needs build/ and a network
./scripts/golden.sh           # score the model's real output on known recordings; about two minutes
```

Run `test.sh` before calling anything done. If the change touches `Sandbox.swift` or how child
processes are launched, run `verify-sandbox.sh` too and read every line, not only the last.
If the change touches `Tuning.swift`, chunking, or the options passed to whisper, run `golden.sh`
and compare its numbers with the ones in `docs/guides/testing.md`.
CI builds and runs the unit tests on every push. It cannot run the model.

## Rules that are not negotiable

1. **No audio is ever lost.** Every instant of a recording belongs to at least one chunk.
   Overlap is acceptable; a gap is not.
2. **Text from a quiet stretch is always fenced and labelled** in the output. Quiet is where the
   model invents text.
3. **Every process that touches audio runs inside the sandbox**, with the network denied. The app
   itself contains no networking code. Do not add any.
4. **Never state a guarantee more strongly than it is checked.** "Enforced" means the kernel blocks
   it and a script proves it. "Audited" means only that the code does not do it.
5. **Never delete or weaken a test to make it pass.** If a test is wrong, stop and say so.
6. **Measure before choosing.** A setting or a speed-up is adopted on a measured result, and the
   number goes in a comment or the commit message.
7. **Nothing personal goes in the repository**: no names, emails, machine names or home-directory
   paths, in files or in commit metadata. Test audio is synthetic only.

## Where the knowledge lives

`docs/guides/` describes how the software works **now**. The README is the front door for people;
the guides are the map for agents and point into the README and the code.

| Guide | Open it when the task touches |
| --- | --- |
| [`overall.md`](docs/guides/overall.md) | anything, first |
| [`how-transcription-works.md`](docs/guides/how-transcription-works.md) | silence detection, chunking, tuning numbers, the Markdown output |
| [`offline-guarantee.md`](docs/guides/offline-guarantee.md) | the sandbox, child processes, anything that reads or writes files |
| [`testing.md`](docs/guides/testing.md) | adding or changing a test |

## How work is done

`docs/tasks/` holds one folder per piece of work, named `YYYY-MM-DD_short-title`, each with a
`plan.md`: background, steps, outcome, constraints, exit criteria, and a note of what went wrong.

- Before starting, write or read the task's `plan.md`. Its exit criteria are the definition of done.
- A task that changes behaviour updates the matching guide, and the README if a claim there
  changes, **in the same commit**.
- A finished task's folder is history. Do not rewrite it.

## Not done yet

Listed so nobody assumes they exist: recordings of real voices, accents or noise in the golden
set (it holds three clear synthetic ones); an automatic check that guides have not gone stale; a home for decision records.
