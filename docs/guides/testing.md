# Testing

## Running the checks

```sh
./scripts/test.sh                              # all unit tests
./scripts/test.sh --filter ChunkPlannerTests   # one file
./scripts/verify-sandbox.sh                    # the sandbox, against the built CLI
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
- Nothing that runs the model is tested automatically. It needs a 3.1 GB file and a GPU.
- There is no scored set of recordings, so tuning changes are judged by eye.
