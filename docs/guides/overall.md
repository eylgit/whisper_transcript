# Transcribe — overall

`recording.m4a → recording.md`, on the user's own Mac, with the network blocked for everything
that touches the audio.

## The pipeline

```text
audio file
  → AudioConverter     convert to 16 kHz mono WAV (Apple's afconvert), beside the source
  → SilenceDetector    measure loudness relative to this recording; find pauses
  → ChunkPlanner       turn pauses into overlapping ranges: speech / silence / speech
  → WhisperRunner      run whisper-cli once per range, no text carried between ranges
  → MarkdownBuilder    join the text; fence and label every quiet stretch
  → recording.md       beside the source
```

`Transcriber.swift` drives those steps. Every child process is launched through
`ProcessRunner.swift`, wrapped by `Sandbox.swift`.

## Code layout

```text
Sources/Core/   TranscribeCore: everything above. A library, so it can be tested
Sources/App/    SwiftUI drag-and-drop front end
Sources/CLI/    command-line front end
Tests/          unit tests for the pure parts of Core
scripts/        build, test, sandbox verification, icon
vendor/         whisper.cpp, pinned to one commit
docs/guides/    how the software works now (this folder)
docs/tasks/     one folder per piece of work, each with a plan.md
```

Both front ends depend on `TranscribeCore` and nothing else, so they cannot drift apart.

## What is pure and what is not

The parts that decide things (`SilenceDetector`, `ChunkPlanner`, `MarkdownBuilder`, the sandbox
profile text, output naming) are plain functions over plain data and are unit tested. The parts
that run the model need a 3.1 GB file and a GPU, so they are exercised by hand, not in CI.

## The guides

| Guide | What it covers |
| --- | --- |
| [`how-transcription-works.md`](how-transcription-works.md) | Why recordings are cut at pauses, how, and the numbers involved |
| [`offline-guarantee.md`](offline-guarantee.md) | What the sandbox enforces, what is only audited, how to prove it |
| [`testing.md`](testing.md) | How to run the checks and what each one protects |
