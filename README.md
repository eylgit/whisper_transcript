# Transcribe

Offline audio → Markdown on macOS, built on [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
and the `large-v3` model.

Drop a recording on the app and get a readable `.md` transcript beside it. Nothing is
uploaded and nothing is cached anywhere you can't see: every process that touches your
audio is cut off from the network by the kernel, not by a promise in a privacy policy.

```
recording.m4a  →  recording.md
```

## At a glance

- **Offline, and enforced.** Every process that touches your audio — `afinfo`,
  `afconvert`, `whisper-cli` — runs under `sandbox-exec` with `(deny network*)`.
  Checked rather than assumed: `curl` returns HTTP 200 outside that profile and cannot
  connect inside it. The bundled `whisper-cli` and its six libraries contain **zero**
  network symbols.
- **No telemetry of any kind.** No analytics, no crash reporting, no update check.
  Nothing is written to user defaults or the system log.
- **Guards against the model's hallucinations** — the reason this exists; see below.
- **Nothing hidden on disk.** Exactly two files, both beside your original. Never
  `/tmp`, never a hidden cache.
- **Reproducible.** whisper.cpp is pinned to an exact commit, and the 3.1 GB model is
  SHA256-verified — setup aborts on a mismatch rather than transcribing with an
  unknown file.
- **No Xcode, no Homebrew, no `sudo`.** Command Line Tools only.
- **The network is used during setup only**, for three things, each named below.

It exists because of one specific problem.

## The problem: Whisper invents speech that was never spoken

Two well-known failure modes of the model, neither of them bugs in whisper.cpp:

**It hallucinates during silence.** Hand the decoder a stretch of quiet on its own
and it reliably produces text anyway — most often something like *"Thank you."*, or
a fragment of subtitle boilerplate from its training data. It was trained on
transcribed speech, so it is disinclined to return nothing.

**It locks into repetition loops.** The decoder carries text between its internal
windows to keep punctuation and sentence structure coherent. Occasionally that
feedback catches, and it emits the same sentence over and over — inventing minutes
of content that was never said. Here is a real run on a test recording, at the point
where it caught:

```
It is usually right, and occasionally confidently wrong. Let us consider the question of privacy.
When you send audio to a computer, it is usually right, and occasionally confidently wrong.
Let us consider the question of privacy. When you send audio to a computer, it is usually right, and occasionally confidently wrong.
Let us consider the question of privacy. When you send audio to a computer, it is usually right, and occasionally confidently wrong.
```

On a two-minute voice memo this is a curiosity. On a one-hour interview with natural
pauses in it, it is the difference between a transcript you can rely on and one you
have to re-listen to in full — which defeats the point of transcribing it.

## What this does about it

**It splits the recording at pauses.** Anything over two minutes is cut at silences
of three seconds or more, and each part is transcribed on its own with no text
carried across the boundary. A decoder that locks into repeating itself therefore
cannot spread past the pause it started in — the loop dies at the cut.

**It finds those pauses relative to the recording itself**, using its own noise floor
and its own speech level, because a fixed threshold is wrong for half of all
recordings: quiet speech in one can sit below room tone in another. If the two are
less than 15 dB apart the recording is too noisy to judge, and it is transcribed in a
single pass rather than cut in the wrong place.

**It never silently drops audio.** Around each pause the audio is covered three times
over:

```
    ...speech A...  [========= pause =========]  ...speech B...
    speech   [ ...A... --- pauseStart+1.5s ]
    silence           [ pauseStart --------- pauseEnd ]
    speech                        [ pauseEnd-1.5s --- ...B... ]
```

Every instant belongs to at least one part. The coverage is deliberately redundant,
because a gap would mean losing spoken words while an overlap only means a duplicated
moment of quiet. And the quiet stretch is transcribed *too*, in case the loudness
measurement was wrong and someone was in fact speaking softly.

**It labels the silence rather than hiding it.** Since quiet stretches are exactly
where the model invents things, they are fenced off in the output:

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
seconds against 39 with it skipped — so it is optional: *Transcribe quiet stretches
too* in the app's Options, or `--skip-silence` on the command line. The gaps are
marked either way, and **the marker says which happened**: *"transcribed separately
as a precaution"* versus *"measured as quiet and skipped, so any speech here was not
captured."* The distinction matters. "We listened and heard nothing" and "we did not
listen" are different claims, and only one of them guarantees nothing was missed.

### Known limitation

**A recording with no long pauses gets no protection.** Chunking can only contain a
loop at a boundary, and a continuous monologue offers none. On such a file the decoder
can still lock up, and nothing in the output will warn you.

This is a deliberate trade. The alternative was disabling the decoder's text
carry-over globally, which measurably degrades punctuation and sentence structure on
*every* recording in order to guard against a failure that affects a few. Pass
`--no-carry-context` to make that trade on a specific file.

Chunking also costs about 3.2 seconds of fixed overhead per part. A one-hour recording
with twenty long pauses runs roughly 10% slower; one with very frequent pauses, worse.

Every tunable number lives in `Sources/Core/Tuning.swift`, each with a comment
explaining what it does and why it is set where it is.

## Install

```sh
./setup.sh
```

Takes about ten minutes. It installs nothing system-wide, needs no `sudo` and no
Homebrew, and requires only the Xcode Command Line Tools.

This is the only point at which anything reaches the network, and it does so for
exactly three things:

| Fetched | From | Notes |
|---|---|---|
| whisper.cpp source | `github.com` | pinned to an exact commit, not a branch |
| `ggml-large-v3.bin`, 3.1 GB | `huggingface.co` | SHA256 verified; setup aborts on mismatch |
| `cmake`, **only if absent** | PyPI, via `uv` or `pip3 --user` | the one dependency macOS doesn't ship |

If `cmake` is already on your `PATH`, that third fetch does not happen. Nothing else in
this project ever opens a socket, before or after setup.

## Use

**App** — drag audio onto `Transcribe.app` or its Dock icon. Multiple files queue up.
There's a progress bar, a Cancel button, and an Options panel for language, translation
and a couple of switches.

**Command line**

```sh
build/transcribe recording.m4a           # → recording.md
build/transcribe *.m4a                   # several at once
build/transcribe -l de recording.wav     # force a language
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

Both sit next to your original, never in `/tmp` and never in a hidden cache. A WAV that
is already 16 kHz mono skips the intermediate file entirely. An existing `.md` is never
overwritten — you get `meeting-1.md` instead, unless you pass `--force`.

Two processes ever touch your audio: Apple's own `/usr/bin/afconvert`, and `whisper-cli`.
There is no ffmpeg and no third-party codec library.

### Honest caveats

Things outside this app's control that still happen on your Mac:

- macOS caches **compiled GPU shaders** in its own cache directory. That's compiled
  graphics code, not your audio — but the sandbox does permit writes there, because
  denying it makes every run 6× slower (19 s vs 3 s on the same clip).
- Writing the `.md` is atomic, which briefly creates a temporary file **in the same
  folder** before renaming it into place. It's transient and in the place you'd expect.
- **Spotlight will index the resulting `.md`**, like any other file you create.
- If you ever **download a prebuilt `.app`** instead of building it here, macOS flags it
  as quarantined and contacts Apple's notarisation service the first time you open it.
  That is Gatekeeper, not this app, and it does not happen to a bundle you built
  yourself from source — the documented path.

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

It is a deny-list rather than an allow-list deliberately: a restrictive allow-list cuts
off the IOKit access Metal needs and silently drops you to far slower CPU inference.

Check it yourself — this tests the *actual* profile the app applies, not a copy:

```sh
./scripts/verify-sandbox.sh
```

It confirms the network is unreachable from inside the sandbox, that writes outside your
audio's folder are refused, that writes beside your audio still work, and that the GPU
still initialises.

### What the sandbox does and does not cover

Precision matters more here than a good soundbite, so: **the sandbox wraps every child
process, not the app itself.** `Transcribe.app` has no App Sandbox entitlement and runs
with your normal user privileges — it is what writes the `.md`.

What that means in practice:

- Everything that ever reads your **audio** — `afinfo`, `afconvert`, `whisper-cli` —
  is kernel-blocked from the network. That part is enforced, and you can verify it
  in one command.
- The app process itself is blocked from the network only by containing no code that
  uses it. That is checkable — grep `Sources/` for `URLSession` and you will find
  nothing — but it is checkable rather than enforced, and the honest word for it is
  *audited*, not *guaranteed*.

## The Neural Engine is slower than the GPU here

whisper.cpp's docs advertise a 3× speedup from Core ML on Apple Silicon. Measured on an
M2 with `large-v3`, it was **1.6× slower** — 2,220 ms vs 1,362 ms per encode. Core ML is
therefore off, which also drops a ~3 GB PyTorch build dependency.
`scripts/make-coreml-encoder.sh` is kept if you want to re-measure on different hardware.

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
compiled directly with `swiftc` from the Command Line Tools — there is no Xcode project
and full Xcode is not required. `Transcribe.app` is self-contained: it carries its own
copy of `whisper-cli`, the dylibs and the model, so it works wherever you move it. The
model is placed with an APFS clone, so it costs no extra disk space.

Rebuild after changing Swift source with:

```sh
./scripts/build-app.sh
```

## Requirements

Apple Silicon Mac, macOS 13+, Xcode Command Line Tools, and about 3.5 GB of disk (almost
all of it the model). `cmake` is fetched automatically if it is missing.

## Licence

MIT — see [LICENSE](LICENSE). [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and
the `ggml-large-v3` model are the work of their own authors, under their own licences.
