# Testing

## Running the checks

```sh
./scripts/test.sh                              # all unit tests
./scripts/test.sh --filter ChunkPlannerTests   # one file
./scripts/verify-sandbox.sh                    # the sandbox, against the built CLI
./scripts/golden.sh                            # the model's real output, against known scripts
```

`test.sh` finds a toolchain that has XCTest (it ships with Xcode, not the Command Line Tools)
without changing the global `xcode-select` setting. CI (`.github/workflows/ci.yml`) builds, runs
the unit tests and checks that the shell scripts parse.

## What each test file protects

| File in `Tests/TranscribeCoreTests/` | What it protects |
| --- | --- |
| `ChunkPlannerTests` | The ranges. One randomised test over 500 made-up recordings asserts that no instant of audio is left uncovered. Named tests pin the edge cases: a pause at the very start, a pause running to the end, two pauses closer than the buffer, unsorted input |
| `SilenceDetectorTests` | Pause detection, against synthesised audio at known levels: found when long enough, ignored when short, same answer loud or faint, and no pauses reported when the recording is too noisy to judge |
| `SandboxTests` | The profile text: network and writes denied, deny before allow, `/` never writable, paths quoted. One test runs `sandbox-exec` for real and confirms the kernel refuses a write outside the allowed folder |
| `MarkdownBuilderTests` | Paragraphs, CJK text joined without spaces, and that a skipped gap and a listened-to gap are worded differently |
| `OutputNamingTests` | An existing `.md` is numbered, never overwritten |
| `ArchitectureTests` | The source, read as text with comments removed: every file in `Sources/Core/` imports only `Foundation`, and no file in `Sources/` mentions `URLSession`, `NWConnection`, `CFNetwork` or `import Network`. A third test feeds each rule a sample, so a rule that matches nothing cannot pass unnoticed. It checks what the code says, not what a process can do; that is `verify-sandbox.sh` |

## The golden set: checking what the model actually returns

Everything above tests the logic around the model. `./scripts/golden.sh` is the only check on
the model's own output. It transcribes each recording in `golden/` for real, compares the result
with the script the recording was made from, and prints one line per run. Add `--verbose` to see
the text behind the numbers. It takes about two minutes and needs the built CLI and the model, so
it runs on your machine and never in CI.

| Column | Meaning |
| --- | --- |
| `errors` | Word error rate of the text **outside** fenced silence blocks: wrong, missing and extra words, as a percentage of the script's words |
| `escaped` | Runs of two or more consecutive words, outside a fence, that do not line up with the script. Text a reader would take as spoken and that was not |
| `fenced` | Words the model produced inside a fenced silence block. Already labelled unreliable, so not held against the run |

Measured on 2026-10-05, identical on three consecutive runs:

| Run | Recording | errors | escaped | fenced | Result |
| --- | --- | --- | --- | --- | --- |
| `standup` | 2 m 19 s, four passages, three gaps of 30 s or more | 0.0 % | 0 | 6 words | PASS |
| `meeting-roomtone` | 46 s, two passages, a 30 s gap filled with faint room noise | 0.0 % | 0 | 0 | PASS |
| `monologue` | 1 m 47 s of continuous speech, no pause to cut at | 30.7 % | 8 | 0 | KNOWN FAILURE |
| `monologue --no-carry-context` | the same recording, carry-forward off | 0.3 % | 0 | 0 | PASS |

Reading those four lines:

- On `standup` the model invented "Thank you." in all three gaps, and all three landed inside a
  fence. That is the design working.
- `monologue` is the known limitation, reproduced: with no pause to cut at, the model locks into
  one sentence, repeats it six times and loses about a third of the script. Nothing in the
  transcript warns the reader. It is marked `known-failure` in the manifest, not hidden and not
  given a generous threshold.
- The same recording with `--no-carry-context` is one word out (it writes "center" for "centre").
  So the fix for a monologue exists and is opt-in; the default trades it for better punctuation
  on everything else.

Thresholds live in `golden/manifest.txt`: at most 2 % word errors and no escaped text. They were
set after the first measured run, not before, because nobody knew what the model would score. A
`known-failure` that starts passing fails the run on purpose, so the manifest gets corrected.

**What this does not prove.** Three recordings, one clear synthetic voice, no background speech,
no accents, no bad microphones. It shows the method works and guards against regressions on
these three. It says nothing about accuracy on real recordings.

**How the comparison is made fair, and no fairer.** Case and punctuation are ignored, hyphens
become spaces, and numerals are spelled out ("4.2" is read as "four point two"), because the
scripts are written as spoken. Nothing else is forgiven; a spelling variant counts as an error.
Details are in the comment at the top of `scripts/golden_score.py`.

## Which test catches what

Be exact about this when describing the tests anywhere.

- The randomised test checks **coverage only**. It would catch lost audio. It does not check how
  a range is labelled.
- A speech range lying inside a pause at the start of a recording is a **labelling** fault, with
  coverage intact. It is caught by `testSilenceAtTheVeryStartDoesNotProduceAZeroWidthChunk`, not
  by the randomised test. This was confirmed by putting the fault back and running both.

## Rules

- A rule that can be a test is a test, not a sentence in a guide.
- Never delete or weaken a test to make it pass.
- To trust a test, see it fail: put the fault back in a scratch copy and check the right test goes red.

## Known limits

- The randomised test uses the system random generator with no fixed seed, so a failure cannot
  be replayed exactly, and it does not shrink to a smallest failing case.
- Nothing that runs the model is tested in CI. It needs a 3.1 GB file and a GPU, so the golden
  set is only as current as the last time someone ran it.
- The golden set is three synthetic recordings. It cannot judge accuracy on real voices.
- The scorer cannot tell an invented phrase from two adjacent misheard words. Both count as escaped.
