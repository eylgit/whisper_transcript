# Initial build



## Background

The owner wanted a small tool for their own use: give it an audio file, get a Markdown
transcript, with nothing leaving the machine. It was built in one day with a coding agent, then
prepared for public view.

The brief, as given at the start: use whisper.cpp with the most capable model; accept common
audio formats; everything offline; no temporary files, or only beside the source file where the
user can see them. The agent was asked to raise the decisions that needed confirming before
building.

## Outcome

- An audio file dropped on the app, or passed to the command line, produces a `.md` transcript beside it.
- Every process that touches the audio is cut off from the network by the operating system.
- Text the speech model invents cannot reach the reader unmarked, and a repetition loop cannot
  spread through the whole transcript.

## Constraints

- Offline after setup. No telemetry, no update check.
- Only two files are written, both beside the source audio.
- No Xcode project, no Homebrew, no `sudo` to build.
- Transcription quality on ordinary recordings must not be traded away to guard against a rare failure.
- Nothing personal in the repository or its history.

## Steps, in the order they happened

1. **The working app.** Audio conversion, the whisper driver, Markdown output, a drag-and-drop
   app and a command-line tool sharing one core, the sandbox, and a one-command setup.
   Three things were measured here rather than assumed:
   - The Core ML encoder, advertised as about 3× faster, measured 1.6× **slower** than the GPU. Disabled.
   - Denying the GPU shader cache made a run take 19 s instead of 3 s. That one folder is allowed.
   - Sandbox rules silently did nothing until paths were fully resolved.
2. **The repetition problem.** On recordings with long silences the model repeated sentences.
   The agent's first fix was to disable the decoder's text carry-forward globally. The owner
   objected that this lowers quality on every recording, and asked for an explanation in plain
   English, the alternatives, and no changes until told to go ahead.
3. **Three options, measured.** Digital silence alone caused no invented text. Carry-forward off
   lost punctuation and cut sentences. A ready-made voice-activity detector was much worse. A
   sweep of decoder settings was also measured and not adopted.
4. **An outside library considered.** A second agent was sent to review it for privacy. It was
   not adopted.
5. **The owner's design: cut at pauses.** Split the recording ourselves, transcribe each part,
   merge. Decided in discussion:
   - Loudness is judged relative to each recording (agent's proposal, accepted).
   - Cuts fall at pauses, not at a target chunk length or inside a search window (owner).
   - One constant, the minimum pause, set to 3 s. Around a pause, three overlapping parts, each
     speech part keeping half the minimum pause as a buffer (owner).
   - The quiet part is transcribed too, in case it is not really silent (owner).
   - Long silences cost time: accepted. Per-part overhead: measured at about 3.2 s, then accepted.
   - The repetition detector and automatic retry: dropped, since a labelled quiet block lets
     the reader judge.
6. **A fault found on the first real run.** A quiet part swallowed the passage after it, because
   whisper reads fixed 30-second windows past the requested end. Segments are now kept only when
   their midpoint falls inside the part that produced them.
7. **Option to skip quiet parts, and descriptive progress.** The label states which happened:
   listened and heard nothing, or did not listen.
8. **Prepared for public view.** A privacy audit of files and history; commit identity rewritten.
   The owner asked the agent to check whether the offline claims were actually true. Two were overstated and were corrected: setup uses the network three times, not once, and the sandbox covers the processes that read audio, not the app itself ("enforced" against "audited").
9. **Tests and CI, after the fact.** The core became a library so it could be tested. 41 unit
   tests and a CI run were added.

## Exit criteria

Written afterwards, with what actually checks each one.

- [x] A recording becomes a `.md` beside it, through both front ends. *Checked by hand on a test recording.*
- [x] The network is unreachable from every process that reads audio. *`scripts/verify-sandbox.sh`.*
- [x] Writes outside the audio's folder are refused. *`scripts/verify-sandbox.sh`, and one unit test that runs the real sandbox.*
- [x] No instant of audio is left uncovered. *Randomised test over 500 made-up recordings.*
- [x] Text from a quiet stretch is always fenced and labelled. *Named unit tests for the chunk plan and the Markdown wording.*
- [x] A loop cannot cross a pause. *Checked by hand on a 2 m 19 s recording with three gaps.*
- [ ] The tuning numbers are validated across real recordings. *Not done. `Tuning.swift` says so.*
- [ ] A recording with no long pause is protected. *Not done, by choice. Documented as a known limitation.*

## What went wrong

- **The tests came after the code.** They were added while preparing the repository for public
  view, not before the logic was written. They then found a fault in code already accepted: a
  recording that opens with a pause produced a "speech" part lying entirely inside the silence,
  so invented text there would have arrived unlabelled.
- **Two fixes were built before the right one.** Carry-forward off, and the voice-activity
  detector. Both were rejected on measured results.
- **"Build complete" was not true.** While adding the tests, the two build products were named
  `transcribe` and `Transcribe`. On a case-insensitive filesystem those are one path, so the app
  overwrote the command-line tool. The build reported success. It was caught only by running the
  tool end to end. Renamed, with the reason in a comment.
- **The README credits the wrong test.** It says the randomised test found the opening-pause
  fault. On 2026-10-05 the fault was put back in a scratch copy: the randomised test still
  passes, and the named test for a pause at the very start fails. The fault is real and is
  pinned; the attribution in the README is not yet corrected. `docs/guides/testing.md` states
  which test catches what.
