<div align="center">

# Transcribe

**Offline audio → Markdown on macOS.**

Not "we don't upload your audio" — *every process that touches it is cut off from the
network by the kernel.*

[![CI](https://github.com/eylgit/whisper_transcript/actions/workflows/ci.yml/badge.svg)](https://github.com/eylgit/whisper_transcript/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-41-brightgreen)](#tests)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20Apple%20Silicon-lightgrey)](#requirements)
[![Licence](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

```
recording.m4a  →  recording.md
```

Built on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and the `large-v3` model.

<sub>
<a href="#why-this-exists">Why</a> ·
<a href="#what-this-does-about-it">How</a> ·
<a href="#install">Install</a> ·
<a href="#use">Use</a> ·
<a href="#the-offline-guarantee-is-enforced-not-promised">Offline guarantee</a> ·
<a href="#tests">Tests</a>
</sub>

</div>

---

Drop a recording on the app and get a readable `.md` transcript beside it.

| | |
|---|---|
| 🔒 **Offline, and enforced** | `afinfo`, `afconvert` and `whisper-cli` all run under `sandbox-exec` with `(deny network*)`. Verified, not assumed: `curl` gets HTTP 200 outside the profile and cannot connect inside it. The bundled binary and its six libraries contain **zero** network symbols. |
| 📡 **No telemetry of any kind** | No analytics, no crash reporting, no update check. Nothing written to user defaults or the system log. |
| 🧠 **Guards against the model's hallucinations** | The reason this exists — [see below](#why-this-exists). |
| 📂 **Nothing hidden on disk** | Exactly two files, both beside your original. Never `/tmp`, never a hidden cache. |
| ♻️ **Reproducible** | whisper.cpp pinned to an exact commit; the 3.1 GB model SHA256-verified. Setup aborts on a mismatch rather than transcribing with an unknown file. |
| 🛠 **No Xcode, no Homebrew, no `sudo`** | Command Line Tools only. |
| ✅ **Tested where it counts** | 41 unit tests over the chunking, silence analysis, sandbox profile and Markdown assembly — including a randomised test asserting no audio can fall between chunks. Writing them [found a real bug](#tests). |
| 🌐 **Network used during setup only** | For exactly three things, [each named below](#install). |

---

## Why this exists

### Whisper invents speech that was never spoken

Two well-known failure modes of the model, neither of them bugs in whisper.cpp.

**1. It hallucinates during silence.** Hand the decoder a stretch of quiet on its own and
it reliably produces text anyway — most often something like *"Thank you."*, or a fragment
of subtitle boilerplate from its training data. It was trained on transcribed speech, so
it is disinclined to return nothing.

**2. It locks into repetition loops.** The decoder carries text between its internal
windows to keep punctuation and sentence structure coherent. Occasionally that feedback
catches, and it emits the same sentence over and over — inventing minutes of content that
was never said.

A real run on a test recording, at the point where it caught:

```text
It is usually right, and occasionally confidently wrong. Let us consider the question of privacy.
When you send audio to a computer, it is usually right, and occasionally confidently wrong.
Let us consider the question of privacy. When you send audio to a computer, it is usually right, and occasionally confidently wrong.
Let us consider the question of privacy. When you send audio to a computer, it is usually right, and occasionally confidently wrong.
```

On a two-minute voice memo this is a curiosity. On a one-hour interview with natural pauses
in it, it is the difference between a transcript you can rely on and one you have to
re-listen to in full — which defeats the point of transcribing it.

---

## What this does about it

### It splits the recording at pauses

Anything over two minutes is cut at silences of three seconds or more, and each part is
transcribed on its own with no text carried across the boundary. A decoder that locks into
repeating itself therefore cannot spread past the pause it started in — **the loop dies at
the cut.**

### It finds those pauses relative to the recording itself

Using the recording's own noise floor and its own speech level, because a fixed threshold
is wrong for half of all recordings: quiet speech in one can sit below room tone in
another. If the two are less than 15 dB apart the recording is too noisy to judge, and it
is transcribed in a single pass rather than cut in the wrong place.

### It never silently drops audio

Around each pause the audio is covered three times over:

```text
    ...speech A...  [========= pause =========]  ...speech B...
    speech   [ ...A... --- pauseStart+1.5s ]
    silence           [ pauseStart --------- pauseEnd ]
    speech                        [ pauseEnd-1.5s --- ...B... ]
```

Every instant belongs to at least one part. The coverage is deliberately redundant, because
a gap would mean losing spoken words while an overlap only means a duplicated moment of
quiet. And the quiet stretch is transcribed *too*, in case the loudness measurement was
wrong and someone was in fact speaking softly.

### It labels the silence rather than hiding it

Since quiet stretches are exactly where the model invents things, they are fenced off in
the output:

```markdown
> ⏸ **Silence — 00:04:32 to 00:04:51** (19s)
> Measured as quiet, transcribed separately as a precaution.
> Treat anything below as unreliable until the end marker.
>
> Thank you.
>
> ⏹ **End of silence — 00:04:51**
```

Transcribing the quiet costs real time — on a test recording that was mostly gaps, 82
seconds against 39 with it skipped — so it is optional: *Transcribe quiet stretches too* in
the app's Options, or `--skip-silence` on the command line.

The gaps are marked either way, and **the marker says which happened**: *"transcribed
separately as a precaution"* versus *"measured as quiet and skipped, so any speech here was
not captured."* The distinction matters. "We listened and heard nothing" and "we did not
listen" are different claims, and only one of them guarantees nothing was missed.

> [!WARNING]
> **Known limitation — a recording with no long pauses gets no protection.**
> Chunking can only contain a loop at a boundary, and a continuous monologue offers none.
> On such a file the decoder can still lock up, and nothing in the output will warn you.
>
> This is a deliberate trade. The alternative was disabling the decoder's text carry-over
> globally, which measurably degrades punctuation and sentence structure on *every*
> recording in order to guard against a failure that affects a few. Pass
> `--no-carry-context` to make that trade on a specific file.

Chunking also costs about 3.2 seconds of fixed overhead per part. A one-hour recording with
twenty long pauses runs roughly 10% slower; one with very frequent pauses, worse.

Every tunable number lives in [`Sources/Core/Tuning.swift`](Sources/Core/Tuning.swift), each
with a comment explaining what it does and why it is set where it is.

---

## Install

```sh
./setup.sh
```

Takes about ten minutes. It installs nothing system-wide, needs no `sudo` and no Homebrew,
and requires only the Xcode Command Line Tools.

This is the only point at which anything reaches the network, and it does so for exactly
three things:

| Fetched | From | Notes |
|---|---|---|
| whisper.cpp source | `github.com` | pinned to an exact commit, not a branch |
| `ggml-large-v3.bin`, 3.1 GB | `huggingface.co` | SHA256 verified; setup aborts on mismatch |
| `cmake`, **only if absent** | PyPI, via `uv` or `pip3 --user` | the one dependency macOS doesn't ship |

If `cmake` is already on your `PATH`, that third fetch does not happen. Nothing else in this
project ever opens a socket, before or after setup.

---

## Use

### App

Drag audio onto `Transcribe.app` or its Dock icon. Multiple files queue up. There's a
progress bar, a Cancel button, and an Options panel for language, translation and a couple
of switches.

### Command line

```sh
build/transcribe recording.m4a           # → recording.md
build/transcribe *.m4a                   # several at once
build/transcribe -l de recording.wav     # force a language
build/transcribe --skip-silence long.m4a # don't transcribe the quiet stretches
build/transcribe --help
```

| Option | | What it does |
|---|---|---|
| `-l` | `--language` | Force a language instead of auto-detecting |
| `-tr` | `--translate` | Translate to English rather than transcribing verbatim |
| `-s` | `--skip-silence` | Don't transcribe quiet stretches (faster; still marked) |
| `-C` | `--no-carry-context` | Disable the decoder's text carry-over entirely |
| `-t` | `--threads` | Thread count |
| `-k` | `--keep-wav` | Keep the intermediate 16 kHz WAV |
| `-f` | `--force` | Overwrite an existing `.md` instead of numbering |
| `-q` | `--quiet` | Suppress progress output |
| | `--print-sandbox-profile` | Print the exact sandbox profile that will be applied |

Accepts anything CoreAudio can read: `wav`, `m4a`, `mp3`, `aac`, `aiff`, `caf`, `flac`.

---

## What this writes to disk

Transcribing `~/Recordings/meeting.m4a` creates exactly two files:

| Path | What | Fate |
|---|---|---|
| `~/Recordings/meeting.whisper-tmp.wav` | 16 kHz mono audio, the only format whisper accepts | deleted once the transcript is written; **kept if the run fails**, so you can inspect it |
| `~/Recordings/meeting.md` | the transcript | yours |

Both sit next to your original, never in `/tmp` and never in a hidden cache. A WAV that is
already 16 kHz mono skips the intermediate file entirely. An existing `.md` is never
overwritten — you get `meeting-1.md` instead, unless you pass `--force`.

Two processes ever touch your audio: Apple's own `/usr/bin/afconvert`, and `whisper-cli`.
There is no ffmpeg and no third-party codec library.

> [!NOTE]
> **Honest caveats** — things outside this app's control that still happen on your Mac:
>
> - macOS caches **compiled GPU shaders** in its own cache directory. That's compiled
>   graphics code, not your audio — but the sandbox does permit writes there, because
>   denying it makes every run 6× slower (19 s vs 3 s on the same clip).
> - Writing the `.md` is atomic, which briefly creates a temporary file **in the same
>   folder** before renaming it into place. It's transient and in the place you'd expect.
> - **Spotlight will index the resulting `.md`**, like any other file you create.
> - If you ever **download a prebuilt `.app`** instead of building it here, macOS flags it
>   as quarantined and contacts Apple's notarisation service the first time you open it.
>   That is Gatekeeper, not this app, and it does not happen to a bundle you built yourself
>   from source — the documented path.

---

## The offline guarantee is enforced, not promised

Every child process runs under `sandbox-exec` with this profile:

```scheme
(version 1)
(allow default)                                   ; Metal keeps its GPU access
(deny network*)                                   ; no network, enforced by the kernel
(deny file-write*)                                ; no writes anywhere...
(allow file-write* (subpath "<your audio's folder>"))   ; ...except beside your audio
(allow file-write* (subpath "<GPU shader cache>"))
```

It is a deny-list rather than an allow-list deliberately: a restrictive allow-list cuts off
the IOKit access Metal needs and silently drops you to far slower CPU inference.

**Check it yourself** — this tests the *actual* profile the app applies, not a copy:

```sh
./scripts/verify-sandbox.sh
```

It confirms the network is unreachable from inside the sandbox, that writes outside your
audio's folder are refused, that writes beside your audio still work, and that the GPU still
initialises.

### What the sandbox does and does not cover

Precision matters more here than a good soundbite, so: **the sandbox wraps every child
process, not the app itself.** `Transcribe.app` has no App Sandbox entitlement and runs with
your normal user privileges — it is what writes the `.md`.

| | Status |
|---|---|
| Everything that reads your **audio** — `afinfo`, `afconvert`, `whisper-cli` | **Enforced.** Kernel-blocked from the network, verifiable in one command. |
| The **app process** itself | **Audited.** Blocked only by containing no code that uses the network — grep `Sources/` for `URLSession` and you find nothing. Checkable, but not enforced, and *audited* is the honest word for it. |

---

## Tests

```sh
./scripts/test.sh
```

The full pipeline needs a 3.1 GB model and a GPU, which makes it a poor thing to assert
against. What is tested instead is everything that is a pure function over plain data, which
is most of the interesting logic.

- **`ChunkPlanner`** — largely one property, checked over 500 randomly shaped recordings:
  *every instant of audio belongs to at least one chunk.* Losing speech in a gap between
  chunks is the worst thing this tool could do, and it would be invisible in the output.
  Named tests pin the edge cases the random one cannot judge, such as how a range is labelled.
  Writing these tests found a real bug — a recording that opens with a pause produced a leading
  "speech" chunk lying entirely inside the silence, which is precisely where the model
  invents text, and it would have reached the transcript unlabelled. To be exact about which
  test catches it: the audio was still fully covered, so the randomised test passes with the
  bug put back. The named test for a pause at the very start is the one that fails.
- **`SilenceDetector`** — against synthesised WAVs at known levels: that a pause is found,
  that one shorter than the minimum is not, that the same *shape* of recording gives the
  same answer whether it is loud or faint, and that a recording with too little dynamic
  range reports **no** pauses rather than guessing at one.
- **`Sandbox`** — that the profile denies network and writes, that the deny rules precede
  the allow rules (these profiles are last-match-wins, so the wrong order fails open and
  silently), and that `/` can never become a writable root. One test runs `sandbox-exec` for
  real and confirms the kernel refuses a write outside the audio's folder.
- **`MarkdownBuilder`** — paragraph breaking, CJK text joined without spaces, and that a
  skipped gap and a listened-to gap carry visibly different wording.
- **Output naming** — that an existing `.md` is numbered rather than overwritten.

The model's own output is scored separately, on your machine, against three synthetic
recordings whose scripts are known:

```sh
./scripts/golden.sh
```

On the two recordings with long gaps it reproduces the script word for word. On the longer of
them the model invents "Thank you." in each of three gaps, and all three land inside a fenced
block. On the third recording, a 107-second monologue with no pause to cut at, the default
settings repeat one sentence six times and score 30.7% word errors — the known limitation
above, measured rather than described. Three clear synthetic
recordings say nothing about real voices or noisy rooms.

> [!IMPORTANT]
> Since the point of this section is that claims should be checkable: XCTest is distributed
> inside Xcode, not the Command Line Tools. **Building** Transcribe needs only the Command
> Line Tools, as documented above; **running the tests** needs Xcode installed.
> `scripts/test.sh` finds a toolchain that has XCTest without changing your global
> `xcode-select` setting.

---

## How it's built

```text
Sources/Core/        TranscribeCore — conversion, chunking, whisper driver, sandbox
Sources/App/         SwiftUI drag-and-drop front end
Sources/CLI/         command line front end
Tests/               unit tests for the pure core
scripts/             build, test, icon generation, sandbox verification, golden-set scoring
golden/              recordings with known correct text, for scoring the model's output
vendor/whisper.cpp   pinned to a specific commit
models/              ggml-large-v3.bin (checksum-verified)
docs/guides/         how the software works now, for coding agents; start at overall.md
docs/tasks/          one dated folder per piece of work, each with a plan.md
CLAUDE.md            the entry point for coding agents: commands, rules, index of guides
```

Both front ends depend on `TranscribeCore` and on nothing else, so they cannot drift apart.
Its public surface is deliberately small — roughly `Layout`, `Sandbox`, `Tuning`,
`WhisperOptions`, `TranscriptionRequest` and `Transcriber.run` — and everything the front
ends do not need stays `internal`. The tests reach the internals with `@testable` rather
than the API being widened to suit them.

It is a SwiftPM package rather than an Xcode project, so `swift build` from the Command Line
Tools is enough and full Xcode is not required to build or install anything.
`Transcribe.app` is self-contained: it carries its own copy of `whisper-cli`, the dylibs and
the model, so it works wherever you move it. The model is placed with an APFS clone, so it
costs no extra disk space.

Rebuild after changing Swift source with:

```sh
./scripts/build-app.sh
```

### The Neural Engine is slower than the GPU here

whisper.cpp's docs advertise a 3× speedup from Core ML on Apple Silicon. Measured on an M2
with `large-v3`, it was **1.6× slower** — 2,220 ms vs 1,362 ms per encode. Core ML is
therefore off, which also drops a ~3 GB PyTorch build dependency.
`scripts/make-coreml-encoder.sh` is kept if you want to re-measure on different hardware.

---

## Requirements

Apple Silicon Mac, macOS 13+, Xcode Command Line Tools, and about 3.5 GB of disk (almost all
of it the model). `cmake` is fetched automatically if it is missing.

## Licence

MIT — see [LICENSE](LICENSE). [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and the
`ggml-large-v3` model are the work of their own authors, under their own licences.
