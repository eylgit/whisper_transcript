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

**Whisper can get stuck repeating itself.** The model sometimes locks into a loop,
emitting one sentence over and over and inventing content that was never spoken. It
happens because each chunk's text is fed forward as context for the next. This app
turns that carry-over off by default (`-mc 0` to whisper.cpp), which eliminated the
loop entirely in testing. The cost is slightly weaker consistency on unusual proper
nouns across a long recording — a good trade when the alternative is fabricated text.
Re-enable it with `--carry-context`, or the matching switch in the app's Options.

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
