# Transcribe

Offline audio → Markdown on macOS, using [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
and the `large-v3` model.

Drop a recording on the app and get a readable `.md` transcript beside it. Nothing
is uploaded, nothing is cached anywhere you can't see, and the network access is
blocked by the operating system rather than by promise.

```
recording.m4a  →  recording.md
```

## Install

```sh
./setup.sh
```

Takes about ten minutes and needs the network exactly once, to clone whisper.cpp
and download the 3.1 GB model (whose checksum is verified). It installs nothing
system-wide, needs no `sudo` and no Homebrew, and requires only the Xcode Command
Line Tools. Afterwards, nothing this app does ever touches the network again.

## Use

**App** — drag audio onto `Transcribe.app` or its Dock icon. Multiple files queue
up. There's a progress bar, a Cancel button, and an Options panel for language,
translation and a couple of switches.

**Command line**

```sh
build/transcribe recording.m4a          # → recording.md
build/transcribe *.m4a                  # several at once
build/transcribe -l de recording.wav    # force a language
build/transcribe --skip-silence long.m4a # don't transcribe the quiet stretches
build/transcribe --help
```

Accepts anything CoreAudio can read: `wav`, `m4a`, `mp3`, `aac`, `aiff`, `caf`, `flac`.

## What this writes to disk

Transcribing `~/Recordings/meeting.m4a` creates exactly two files:

| Path | What | Fate |
|---|---|---|
| `~/Recordings/meeting.whisper-tmp.wav` | 16 kHz mono audio, the only format whisper accepts | deleted once the transcript is written; **kept if the run fails**, so you can inspect it |
| `~/Recordings/meeting.md` | the transcript | yours |

Both sit next to your original, never in `/tmp` and never in a hidden cache. A WAV
that is already 16 kHz mono skips the intermediate file entirely. An existing
`.md` is never overwritten — you get `meeting-1.md` instead, unless you pass `--force`.

Two processes ever touch your audio: Apple's own `/usr/bin/afconvert`, and
`whisper-cli`. There is no ffmpeg and no third-party codec library.

### Honest caveats

Things outside this app's control that still happen on your Mac:

- macOS caches **compiled GPU shaders** in its own cache directory. That's compiled
  graphics code, not your audio — but the sandbox does permit writes there, because
  denying it makes every run 6× slower (19 s vs 3 s on the same clip).
- Writing the `.md` is atomic, which briefly creates a temporary file **in the same
  folder** before renaming it into place. It's transient and in the place you'd expect.
- **Spotlight will index the resulting `.md`**, like any other file you create.

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

It is a deny-list rather than an allow-list deliberately: a restrictive allow-list
cuts off the IOKit access Metal needs and silently drops you to far slower CPU
inference.

Check it yourself — this tests the *actual* profile the app applies, not a copy:

```sh
./scripts/verify-sandbox.sh
```

It confirms the network is unreachable from inside the sandbox, that writes outside
your audio's folder are refused, that writes beside your audio still work, and that
the GPU still initialises.

## Two things worth knowing

**The Neural Engine is slower than the GPU here.** whisper.cpp's docs advertise a
3× speedup from Core ML on Apple Silicon. Measured on an M2 with `large-v3`, it was
**1.6× slower** — 2,220 ms vs 1,362 ms per encode. Core ML is therefore off, which
also drops a ~3 GB PyTorch build dependency. `scripts/make-coreml-encoder.sh` is
kept if you want to re-measure on different hardware.

**Whisper can get stuck repeating itself.** The decoder sometimes locks into a
loop, emitting one sentence over and over and inventing content that was never
spoken. It also invents text during silence — a stretch of quiet handed to it on
its own reliably produces something like *"Thank you."* Neither is a bug in this
app; both are well-known behaviours of the model.

## How long recordings are handled

Recordings over two minutes are split at pauses of three seconds or more, and
each part is transcribed on its own with no text carried across the boundary. A
decoder that locks into repeating itself therefore cannot spread past the pause
it started in.

Pauses are found by measuring loudness **relative to the recording itself** —
its own noise floor and its own speech level — because a fixed threshold is
wrong for half of all recordings: quiet speech in one can sit below room tone in
another. If the two are less than 15 dB apart the recording is too noisy to
judge, and it is transcribed in a single pass rather than cut in the wrong place.

Around each pause the audio is covered three times over:

```
    ...speech A...  [========= pause =========]  ...speech B...
    speech   [ ...A... --- pauseStart+1.5s ]
    silence           [ pauseStart --------- pauseEnd ]
    speech                        [ pauseEnd-1.5s --- ...B... ]
```

Two things follow from that shape. Every instant of audio belongs to at least
one part, so no words can fall in a crack — coverage is deliberately redundant,
because a gap would mean silently losing speech while an overlap only means a
duplicated moment of quiet. And the quiet stretch is **transcribed too**, in
case the loudness measurement was wrong and someone was in fact speaking softly.

That last part is optional — *Transcribe quiet stretches too* in the app's
Options, or `--skip-silence` on the command line — because it costs real time.
On a test recording that was mostly gaps, transcribing them took 82 seconds
against 39 with them skipped. Turning it off is faster and produces a tidier
transcript, but anything spoken too softly to register is then lost. The gaps
are marked either way, and the marker says which happened: *"transcribed
separately as a precaution"* versus *"measured as quiet and skipped, so any
speech here was not captured."* The distinction matters — "we listened and heard
nothing" and "we did not listen" are different claims, and only one of them
guarantees nothing was missed.

Because quiet stretches are exactly where the model invents things, they are
fenced off and labelled in the transcript:

```markdown
> ⏸ **Silence — 00:04:32 to 00:04:51** (19s)
> Measured as quiet, transcribed separately as a precaution.
> Treat anything below as unreliable until the end marker.
>
> Thank you.
>
> ⏹ **End of silence — 00:04:51**
```

Every tunable number lives in `Sources/Core/Tuning.swift`, each with a comment
explaining what it does and why it is set where it is.

### Known limitation

**A recording with no long pauses gets no protection.** Chunking can only
contain a loop at a boundary, and a continuous monologue offers none. On such a
file the decoder can still lock up, and nothing in the output will warn you.
This is a deliberate trade: the alternative was disabling the text carry-over
globally, which measurably degrades punctuation and sentence structure on
*every* recording to guard against a failure that affects a few. Pass
`--no-carry-context` to make that trade on a specific file.

There is also a cost: each part carries about 3.2 seconds of fixed overhead.
A one-hour recording with twenty long pauses runs roughly 10% slower. A
recording with very frequent long pauses would be worse.

## How it's built

```
Sources/Core/     audio conversion, whisper driver, Markdown assembly, sandbox
Sources/App/      SwiftUI drag-and-drop front end
Sources/CLI/      command line front end
scripts/          build, icon generation, sandbox verification
vendor/whisper.cpp   pinned to a specific commit
models/           ggml-large-v3.bin (checksum-verified)
```

Both front ends share `Sources/Core` verbatim, so they cannot drift apart. Swift is
compiled directly with `swiftc` from the Command Line Tools — there is no Xcode
project and full Xcode is not required. `Transcribe.app` is self-contained: it
carries its own copy of `whisper-cli`, the dylibs and the model, so it works
wherever you move it. The model is placed with an APFS clone, so it costs no extra
disk space.

Rebuild after changing Swift source with:

```sh
./scripts/build-app.sh
```

## Requirements

Apple Silicon Mac, macOS 13+, Xcode Command Line Tools, and about 3.5 GB of disk
(almost all of it the model). `cmake` is fetched automatically if it is missing.
